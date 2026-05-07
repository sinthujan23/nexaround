import cv2
import numpy as np
import os
import logging

logger = logging.getLogger(__name__)

class LocalVisionService:
    def __init__(self):
        # MobileNet-SSD classes
        self.classes = [
            "background", "aeroplane", "bicycle", "bird", "boat",
            "bottle", "bus", "car", "cat", "chair", "cow", "diningtable",
            "dog", "horse", "motorbike", "person", "pottedplant", "sheep",
            "sofa", "train", "tvmonitor"
        ]
        
        base_dir = os.path.dirname(os.path.dirname(__file__))
        prototxt = os.path.join(base_dir, "models", "mobile_net_ssd.prototxt")
        model = os.path.join(base_dir, "models", "mobile_net_ssd.caffemodel")
        
        if os.path.exists(prototxt) and os.path.exists(model):
            try:
                self.net = cv2.dnn.readNetFromCaffe(prototxt, model)
                self.enabled = True
                logger.info("Local Vision (MobileNet-SSD) loaded successfully.")
            except Exception as e:
                logger.error(f"Error loading local vision model: {e}")
                self.enabled = False
        else:
            logger.warning(f"Local vision models not found at {prototxt}. Local mode disabled.")
            self.enabled = False

    def identify(self, image_bytes: bytes):
        if not self.enabled:
            return None
            
        try:
            nparr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            (h, w) = img.shape[:2]
            
            # Pre-process image for MobileNet-SSD
            blob = cv2.dnn.blobFromImage(cv2.resize(img, (300, 300)), 0.007843, (300, 300), 127.5)
            self.net.setInput(blob)
            detections = self.net.forward()
            
            best_detection = None
            max_confidence = 0.2 # Threshold
            
            for i in range(0, detections.shape[2]):
                confidence = detections[0, 0, i, 2]
                if confidence > max_confidence:
                    idx = int(detections[0, 0, i, 1])
                    if idx < len(self.classes):
                        class_name = self.classes[idx]
                        if confidence > max_confidence:
                            max_confidence = confidence
                            best_detection = class_name
            
            if best_detection:
                return {
                    "object_name": best_detection.capitalize(),
                    "category": "Local Discovery",
                    "significance": f"Detected locally as a {best_detection}.",
                    "interesting_fact": "This was identified without using any cloud API.",
                    "real_time_info": "Offline mode active.",
                    "accuracy_confidence": float(max_confidence)
                }
            
            return {
                "object_name": "Unknown Object",
                "category": "Local Discovery",
                "significance": "Nothing specific could be identified locally.",
                "interesting_fact": "Local models are smaller and might miss specific details.",
                "real_time_info": "Offline mode active.",
                "accuracy_confidence": 0.0
            }
            
        except Exception as e:
            logger.error(f"Local identification error: {e}")
            return None

local_vision_service = LocalVisionService()
