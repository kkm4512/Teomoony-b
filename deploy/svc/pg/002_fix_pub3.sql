UPDATE svc.publish SET status = 'failed', finished_at = now(), note = note || ' · 23:50 workers 4→8 로 다시 걸며 멈춤(담긴 줄은 그대로 유효)' WHERE publish_id = 3 AND status = 'running';
