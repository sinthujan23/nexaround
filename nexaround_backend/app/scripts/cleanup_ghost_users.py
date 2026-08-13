"""Script to identify and purge zero-activity ghost/synthetic accounts from the database."""
import asyncio
import sys
import argparse
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.core.config import settings

# List of known developer/team accounts to NEVER touch
PROTECTED_EMAILS = {
    "sinthujan@hashnate.com",
    "ilham@hashnate.com",
    "faris@hashnate.com",
    "sinthujansiveswaran1@gmail.com",
    "sinthujansiveswaran71@gmail.com",
    "sinthujansiveswaran9@gmail.com",
    "sinthusives@gmail.com",
    "sinthusives2@gmail.com",
    "karumpulihero@gmail.com",
    "jawajawaharsha@gmail.com",
    "jawa@gmail.com",
    "shavmiyanviji@gmail.com",
    "rayeesfarook@gmail.com",
    "musnymohammed@gmail.com",
    "mohamedmuzakkir7@gmail.com",
    "bombayism@gmail.com",
    "aakifaniyas@gmail.com",
    "marsooknoosha@gmail.com",
}


async def main():
    parser = argparse.ArgumentParser(description="Clean up ghost/synthetic user accounts.")
    parser.add_argument("--purge", action="store_true", help="Permanently delete candidate ghost accounts")
    parser.add_argument("--deactivate", action="store_true", help="Deactivate candidate accounts without deleting")
    parser.add_argument("--dry-run", action="store_true", default=True, help="Preview accounts without making changes (default)")
    args = parser.parse_args()

    # Determine execution mode
    purge_mode = args.purge
    deactivate_mode = args.deactivate and not purge_mode
    dry_run = not (purge_mode or deactivate_mode)

    print("=" * 80)
    if purge_mode:
        print("🔥 MODE: PURGE (Deleting accounts from database)")
    elif deactivate_mode:
        print("🚫 MODE: DEACTIVATE (Setting is_active = False)")
    else:
        print("🔍 MODE: DRY-RUN (Previewing candidate accounts)")
    print("=" * 80)

    db_url = settings.DATABASE_URL
    # If running inside docker container or host
    if "localhost" in db_url:
        # Try container hostname fallback if localhost fails
        pass

    engine = create_async_engine(db_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        # Query candidates: Users with ZERO activity across all tables
        result = await session.execute(text("""
            SELECT u.id, u.email, u.display_name, u.created_at, u.password_hash IS NOT NULL as has_pw
            FROM users u
            LEFT JOIN travel_stories ts ON ts.user_id = u.id
            LEFT JOIN reviews r ON r.user_id = u.id
            LEFT JOIN itineraries i ON i.user_id = u.id
            LEFT JOIN budgets b ON b.user_id = u.id
            LEFT JOIN discovery_histories dh ON dh.user_id = u.id
            LEFT JOIN user_sessions us ON us.user_id = u.id
            WHERE ts.id IS NULL 
              AND r.id IS NULL 
              AND i.id IS NULL 
              AND b.id IS NULL 
              AND dh.id IS NULL
              AND us.id IS NULL
            ORDER BY u.created_at ASC
        """))
        candidates = result.fetchall()

        ghosts = [c for c in candidates if c[1] not in PROTECTED_EMAILS]

        print(f"\nFound {len(ghosts)} ghost accounts with 0 activity:\n")

        for i, g in enumerate(ghosts, 1):
            uid, email, name, created, has_pw = g
            reg = "Email/PW" if has_pw else "Social/OAuth"
            print(f"  [{i:2d}] {email:40s} │ {name:20s} │ {reg:12s} │ Created: {created}")

        if not ghosts:
            print("\n✅ No ghost accounts found to clean up.")
            await engine.dispose()
            return

        if dry_run:
            print("\n💡 This was a dry run. To execute cleanup, run:")
            print("   python3 app/scripts/cleanup_ghost_users.py --purge")
            print("   python3 app/scripts/cleanup_ghost_users.py --deactivate")
        else:
            ghost_ids = [str(g[0]) for g in ghosts]
            if deactivate_mode:
                print(f"\nDeactivating {len(ghost_ids)} accounts...")
                await session.execute(text("""
                    UPDATE users SET is_active = False WHERE id::text = ANY(:ids)
                """), {"ids": ghost_ids})
                await session.commit()
                print("✅ Successfully deactivated ghost accounts!")
            elif purge_mode:
                print(f"\nDeleting {len(ghost_ids)} accounts...")
                await session.execute(text("""
                    DELETE FROM notifications WHERE user_id::text = ANY(:ids)
                """), {"ids": ghost_ids})
                await session.execute(text("""
                    DELETE FROM users WHERE id::text = ANY(:ids)
                """), {"ids": ghost_ids})
                await session.commit()
                print("✅ Successfully purged ghost accounts!")

    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
