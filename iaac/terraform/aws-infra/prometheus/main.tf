resource "aws_prometheus_workspace" "kubeflow_prometheus" {
  alias = "kubeflow-${var.stage}"
}