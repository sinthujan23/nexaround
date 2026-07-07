import cv2
import numpy as np
import os
import math

def create_museum_animation():
    # Video settings
    width = 1200
    height = 400
    fps = 30
    duration_sec = 8
    total_frames = fps * duration_sec
    output_filename = "museum_banner.mp4"

    print(f"Generating {output_filename} ({width}x{height}, {fps}fps, {duration_sec}s)...")

    # Define color scheme (BGR format for OpenCV)
    # Deep midnight blue to dark charcoal background gradient colors
    bg_center_color = np.array([25, 15, 10])  # Deep Indigo/Blue-Grey in BGR
    bg_outer_color = np.array([12, 10, 8])    # Near Black in BGR

    # Action Teal: #007A7C -> RGB(0, 122, 124) -> BGR(124, 122, 0)
    brand_teal = (124, 122, 0)
    # Deep Violet: BGR(200, 50, 100)
    brand_violet = (200, 50, 100)
    # Bright Cyan: BGR(240, 240, 50)
    brand_cyan = (240, 240, 50)

    # Museum list to display
    museums = [
        {"name": "LOUVRE MUSEUM", "color": brand_teal},
        {"name": "VATICAN MUSEUMS", "color": brand_violet},
        {"name": "SHENZHEN MUSEUM", "color": brand_cyan},
        {"name": "BRITISH MUSEUM", "color": brand_teal},
        {"name": "HERMITAGE MUSEUM", "color": brand_violet},
        {"name": "THE MET", "color": brand_cyan}
    ]

    # Initialize particle system
    np.random.seed(42)
    num_particles = 70
    particles = []
    for i in range(num_particles):
        # Base orbit center
        cx = np.random.uniform(50, width - 50)
        cy = np.random.uniform(50, height - 50)
        
        # Orbit radii
        rx = np.random.uniform(20, 60)
        ry = np.random.uniform(20, 60)
        
        # Speed and direction phase
        phase = np.random.uniform(0, 2 * np.pi)
        speed_mult = np.random.choice([1, 2])  # Must be integer for seamless loop
        
        # Size of the node
        size = np.random.uniform(2, 6)
        
        # Core color
        color_choice = np.random.choice([0, 1, 2], p=[0.5, 0.3, 0.2])
        if color_choice == 0:
            color = brand_teal
        elif color_choice == 1:
            color = brand_violet
        else:
            color = brand_cyan
            
        particles.append({
            "cx": cx, "cy": cy,
            "rx": rx, "ry": ry,
            "phase": phase,
            "speed_mult": speed_mult,
            "size": size,
            "color": color,
            "museum_idx": i if i < len(museums) else -1
        })

    # Initialize Video Writer
    # Use MP4V codec for high compatibility
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output_filename, fourcc, fps, (width, height))

    if not out.isOpened():
        print("Error: Could not open VideoWriter.")
        return

    # Generate frames
    for frame_idx in range(total_frames):
        # Progress from 0 to 2*pi
        theta = (frame_idx / total_frames) * 2 * np.pi

        # 1. Background gradient (Radial gradient from center)
        frame = np.zeros((height, width, 3), dtype=np.uint8)
        # Create gradient grid
        y_indices, x_indices = np.indices((height, width))
        dy = (y_indices - height / 2) / (height / 2)
        dx = (x_indices - width / 2) / (width / 2)
        dist = np.sqrt(dx*dx + dy*dy)
        dist = np.clip(dist, 0.0, 1.0)
        
        # Interpolate BGR
        for c in range(3):
            frame[:, :, c] = bg_center_color[c] * (1.0 - dist) + bg_outer_color[c] * dist

        # 2. Update particle positions
        positions = []
        for p in particles:
            angle = theta * p["speed_mult"] + p["phase"]
            x = int(p["cx"] + p["rx"] * np.cos(angle))
            y = int(p["cy"] + p["ry"] * np.sin(angle))
            positions.append((x, y))

        # 3. Draw connecting lines (Constellation connections)
        max_dist = 110
        for i in range(num_particles):
            x1, y1 = positions[i]
            for j in range(i + 1, num_particles):
                x2, y2 = positions[j]
                d = math.hypot(x2 - x1, y2 - y1)
                if d < max_dist:
                    alpha = 1.0 - (d / max_dist)
                    # Smooth curve interpolation for intensity
                    alpha = alpha * alpha 
                    
                    # Compute average color for connection
                    c1 = np.array(particles[i]["color"])
                    c2 = np.array(particles[j]["color"])
                    line_color = ((c1 + c2) / 2).astype(int).tolist()
                    
                    # Blend line color with background
                    overlay = frame.copy()
                    cv2.line(overlay, (x1, y1), (x2, y2), line_color, 1, cv2.LINE_AA)
                    cv2.addWeighted(overlay, alpha * 0.45, frame, 1 - (alpha * 0.45), 0, frame)

        # 4. Draw glowing nodes
        for i, p in enumerate(particles):
            x, y = positions[i]
            size = p["size"]
            color = p["color"]

            # Outer glow (drawn on overlay for blending)
            overlay = frame.copy()
            cv2.circle(overlay, (x, y), int(size * 3), color, -1, cv2.LINE_AA)
            cv2.addWeighted(overlay, 0.25, frame, 0.75, 0, frame)

            # Core
            cv2.circle(frame, (x, y), int(size), (255, 255, 255), -1, cv2.LINE_AA)
            cv2.circle(frame, (x, y), int(max(1, size - 1.5)), color, 1, cv2.LINE_AA)

        # 5. Draw museum labels with glow
        for i, p in enumerate(particles):
            m_idx = p["museum_idx"]
            if m_idx != -1:
                x, y = positions[i]
                museum_name = museums[m_idx]["name"]
                m_color = museums[m_idx]["color"]
                
                # Setup font properties
                font = cv2.FONT_HERSHEY_SIMPLEX
                font_scale = 0.45
                thickness = 1
                
                # Offset text position slightly above the node
                text_x = x + 10
                text_y = y - 10
                
                # Check bounds to keep text inside the frame
                (w_text, h_text), baseline = cv2.getTextSize(museum_name, font, font_scale, thickness)
                if text_x + w_text > width:
                    text_x = x - w_text - 10
                if text_y - h_text < 0:
                    text_y = y + h_text + 15
                
                # Draw dark shadow / glow behind text
                cv2.putText(frame, museum_name, (text_x + 1, text_y + 1), font, font_scale, (10, 10, 10), thickness + 3, cv2.LINE_AA)
                cv2.putText(frame, museum_name, (text_x, text_y), font, font_scale, (10, 10, 10), thickness + 2, cv2.LINE_AA)
                
                # Subtle colored glow overlay
                overlay = frame.copy()
                cv2.putText(overlay, museum_name, (text_x, text_y), font, font_scale, m_color, thickness, cv2.LINE_AA)
                cv2.addWeighted(overlay, 0.7, frame, 0.3, 0, frame)
                
                # White main text
                cv2.putText(frame, museum_name, (text_x, text_y), font, font_scale, (255, 255, 255), thickness, cv2.LINE_AA)

        # 6. Subtle pulsing global overlay vignette (to give dynamic breathing effect)
        pulse = 0.5 + 0.5 * math.sin(theta * 2)  # pulses twice per video duration
        overlay = frame.copy()
        cv2.circle(overlay, (width // 2, height // 2), width // 2, brand_teal, -1)
        cv2.addWeighted(overlay, 0.05 + 0.03 * pulse, frame, 0.95 - 0.03 * pulse, 0, frame)

        # Write frame
        out.write(frame)

    out.release()
    print(f"Successfully generated {output_filename}!")

if __name__ == "__main__":
    create_museum_animation()
