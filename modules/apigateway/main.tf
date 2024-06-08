resource "aws_apigatewayv2_api" "simplyblock_api" {
  name          = "${terraform.workspace}-simplyblock-mgmt-api-http"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_vpc_link" "vpc_link" {
  name               = "${terraform.workspace}-simplyblock-vpclink"
  security_group_ids = [var.api_gateway_id]
  subnet_ids         = var.public_subnets
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.simplyblock_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.root_integration.id}"
}

resource "aws_apigatewayv2_integration" "root_integration" {
  api_id             = aws_apigatewayv2_api.simplyblock_api.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.vpc_link.id
  integration_uri    = length(var.mgmt_node_instance_ids) > 1 ? aws_lb_listener.root_lb_listener.arn : aws_service_discovery_service.root_service.arn
}

resource "aws_service_discovery_http_namespace" "mgmt_api" {
  name = "${terraform.workspace}-simplyblock-mgmt-api"
}

resource "aws_service_discovery_service" "root_service" {
  name         = "${terraform.workspace}-simplyblock-root-svc"
  namespace_id = aws_service_discovery_http_namespace.mgmt_api.id
  type         = "HTTP"
}

resource "aws_service_discovery_instance" "root_endpoint" {
  instance_id = var.mgmt_node_instance_ids[0]
  service_id  = aws_service_discovery_service.root_service.id

  attributes = {
    AWS_INSTANCE_IPV4 = var.mgmt_node_private_ips[0]
    AWS_INSTANCE_PORT = "80"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.simplyblock_api.id
  name        = "$default"
  auto_deploy = true
}

# Create Load Balancer
resource "aws_lb" "root_internal_lb" {
  name               = "${terraform.workspace}-root-lb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.public_subnets
  security_groups    = [var.api_gateway_id]
}

# Create Target Group
resource "aws_lb_target_group" "root_target" {
  name     = "${terraform.workspace}-root-target-group"
  port     = 80
  protocol = "TCP"
  vpc_id   = var.vpc_id
}

resource "aws_lb_target_group_attachment" "root_target_attachment" {
  count              = length(var.mgmt_node_instance_ids)
  target_group_arn   = aws_lb_target_group.root_target.arn
  target_id          = var.mgmt_node_instance_ids[count.index]
  port               = 80
}

# Create Listener
resource "aws_lb_listener" "root_lb_listener" {
  load_balancer_arn = aws_lb.root_internal_lb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.root_target.arn
  }
}

output "api_invoke_url" {
  value = "https://${aws_apigatewayv2_api.simplyblock_api.id}.execute-api.${var.region}.amazonaws.com/"
}
