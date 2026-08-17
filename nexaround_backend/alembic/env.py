import os
import sys
import asyncio
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from alembic import context

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from app.core.database import Base
from app.core.config import settings
import app.models  # ensure models are registered

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Interpret the config file for Python logging.
# This line sets up loggers basically.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# add your model's MetaData object here
# for 'autogenerate' support
target_metadata = Base.metadata

# other values from the config, defined by the needs of env.py,
# can be acquired:
# my_important_option = config.get_main_option("my_important_option")
# ... etc.


def include_object(object, name, type_, reflected, compare_to):
    if type_ == "table" and name in {
        "spatial_ref_sys", "topology", "layer", "countysub_lookup",
        "county_lookup", "zip_state_loc", "zip_state", "zip_lookup",
        "county", "state", "place_lookup", "street_type_lookup", 
        "direction_lookup", "secondary_unit_lookup", "geocode_settings", 
        "geocode_settings_default", "loader_lookuptables", "loader_platform", 
        "loader_variables", "pagc_gaz", "pagc_lex", "pagc_rules"
    }:
        return False
    if type_ == "table" and reflected and target_metadata.tables.get(name) is None:
        return False
    # api_events is RANGE-partitioned and its partitions are managed by
    # ensure_api_events_partition(). Autogenerate has no DDL for either, so it
    # would emit a plain CREATE TABLE and try to drop every child partition.
    if name == "api_events" or (name or "").startswith("api_events_"):
        return False
    if type_ == "table" and object is not None and \
            object.info.get("skip_autogenerate"):
        return False
    return True

def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode.

    This configures the context with just a URL
    and not an Engine, though an Engine is acceptable
    here as well.  By skipping the Engine creation
    we don't even need a DBAPI to be available.

    Calls to context.execute() here emit the given string to the
    script output.

    """
    url = settings.DATABASE_URL
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        include_object=include_object,
    )

    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(
        connection=connection, 
        target_metadata=target_metadata,
        include_object=include_object,
    )

    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    """In this scenario we need to create an Engine
    and associate a connection with the context.

    """
    configuration = config.get_section(config.config_ini_section, {})
    configuration["sqlalchemy.url"] = settings.DATABASE_URL
    
    connectable = async_engine_from_config(
        configuration,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)

    await connectable.dispose()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode."""

    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
