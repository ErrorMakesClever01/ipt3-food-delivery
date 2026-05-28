output "alb_dns_name" { value = aws_lb.main.dns_name }
output "alb_zone_id" { value = aws_lb.main.zone_id }
output "alb_arn" { value = aws_lb.main.arn }
output "frontend_tg_arn" { value = aws_lb_target_group.frontend.arn }
output "backend_tg_arn" { value = aws_lb_target_group.backend.arn }
output "admin_tg_arn" { value = aws_lb_target_group.admin.arn }
