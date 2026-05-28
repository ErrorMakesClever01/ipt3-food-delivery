output "mongodb_secret_arn" { value = aws_secretsmanager_secret.mongodb.arn }
output "jenkins_secret_arn" { value = aws_secretsmanager_secret.jenkins.arn }
output "dockerhub_secret_arn" { value = aws_secretsmanager_secret.dockerhub.arn }
output "app_instance_profile_name" { value = aws_iam_instance_profile.app.name }
output "app_iam_role_arn" { value = aws_iam_role.app_role.arn }
