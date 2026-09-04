# Integration contracts only. They deliberately do not create shared platform services.
# front_door records a selected follow-on integration; application_gateway is PREVIEW.
resource "terraform_data" "front_door_integration" {
  count = var.ingress_mode == "front_door" ? 1 : 0
  input = {
    status       = "integration-required"
    cluster_id   = azurerm_redhat_openshift_cluster.aro.id
    ingress_mode = var.ingress_mode
  }
}

resource "terraform_data" "application_gateway_preview" {
  count = var.ingress_mode == "application_gateway" ? 1 : 0
  input = {
    status       = "preview-not-provisioned"
    cluster_id   = azurerm_redhat_openshift_cluster.aro.id
    ingress_mode = var.ingress_mode
  }
}
