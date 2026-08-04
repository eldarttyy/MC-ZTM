output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet."
  value       = aws_subnet.private.id
}

output "workload_security_group_id" {
  description = "ID of the workload security group."
  value       = aws_security_group.workload.id
}

output "workload_role_arn" {
  description = "ARN of the workload instance role."
  value       = aws_iam_role.workload.arn
}

output "workload_instance_profile" {
  description = "Name of the workload instance profile."
  value       = aws_iam_instance_profile.workload.name
}

output "flow_log_group" {
  description = "CloudWatch log group receiving VPC flow logs, if enabled."
  value       = try(aws_cloudwatch_log_group.flow_logs[0].name, null)
}
