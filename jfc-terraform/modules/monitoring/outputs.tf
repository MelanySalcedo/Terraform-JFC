output "sns_topic_arn" {
  description = "SNS topic ARN for alarms"
  value       = aws_sns_topic.alarms.arn
}

output "alarm_names" {
  description = "List of created alarm names"
  value = [
    aws_cloudwatch_metric_alarm.ecs_cpu_high.alarm_name,
    aws_cloudwatch_metric_alarm.ecs_memory_high.alarm_name,
    aws_cloudwatch_metric_alarm.aurora_cpu_high.alarm_name,
    aws_cloudwatch_metric_alarm.redis_memory_high.alarm_name,
    aws_cloudwatch_metric_alarm.alb_5xx_errors.alarm_name,
    aws_cloudwatch_metric_alarm.alb_unhealthy_targets.alarm_name,
  ]
}
