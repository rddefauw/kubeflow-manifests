output "prometheus_ws_arn" {
    value = aws_prometheus_workspace.kubeflow_prometheus.arn
}
output "prometheus_ws_id" {
    value = aws_prometheus_workspace.kubeflow_prometheus.id
}
output "prometheus_ws_prometheus_endpoint" {
    value = aws_prometheus_workspace.kubeflow_prometheus.prometheus_endpoint 
}