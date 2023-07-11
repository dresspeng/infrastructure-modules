
# -----------------
#     ACM
# -----------------
data "aws_route53_zone" "this" {
  for_each = { for listener in var.traffic.listeners : "${var.acm.record.subdomain_name}" => {} if listener.protocol == "https" }

  name         = var.acm.zone_name
  private_zone = false
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "4.3.2"

  for_each = { for listener in var.traffic.listeners : "${var.acm.record.subdomain_name}" => {} if listener.protocol == "https" }

  create_certificate     = true
  create_route53_records = true

  key_algorithm     = "RSA_2048"
  validation_method = "DNS"

  domain_name = "${var.acm.record.subdomain_name}.${var.acm.zone_name}"
  zone_id     = data.aws_route53_zone.this[var.acm.record.subdomain_name].zone_id

  subject_alternative_names = [for extension in distinct(compact(var.acm.record.extensions)) : "${extension}.${var.acm.record.subdomain_name}.${var.acm.zone_name}"]

  wait_for_validation = true
  validation_timeout  = "15m"

  tags = var.common_tags
}

# -----------------
#     Route53
# -----------------
// ecs service discovery is alternative to route53
module "route53_records" {
  source = "../../../../module/aws/network/route53/record"

  for_each = { for k, v in var.route53 != null ? { "${var.route53.record.subdomain_name}" = {} } : {} : k => v }

  zone_name = var.route53.zone.name
  record = {
    subdomain_name = var.route53.record.subdomain_name
    extensions     = var.route53.record.extensions
    type           = "A"
    alias = {
      name    = "dualstack.${module.elb.lb_dns_name}"
      zone_id = module.elb.lb_zone_id
    }
  }

  depends_on = [module.elb]
}

# Cognito for authentication: https://github.com/terraform-aws-modules/terraform-aws-alb/blob/master/examples/complete-alb/main.tf
module "elb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "8.6.0"

  name = var.common_name

  load_balancer_type = "application"

  vpc_id          = var.vpc.id
  subnets         = local.subnets
  security_groups = [module.elb_sg.security_group_id]

  http_tcp_listeners = [
    for listener in var.traffic.listeners : {
      port               = listener.port
      protocol           = try(var.protocols[listener.protocol], "TCP")
      target_group_index = 0
    } if listener.protocol == "http"
  ]

  https_listeners = [
    for listener in var.traffic.listeners : {
      port               = listener.port
      protocol           = try(var.protocols[listener.protocol], "TCP")
      certificate_arn    = module.acm[var.acm.record.subdomain_name].acm_certificate_arn
      target_group_index = 0
    } if listener.protocol == "https" && var.acm != null
  ]

  // forward listener to target
  // https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html#target-group-protocol-version
  target_groups = [
    {
      name             = var.common_name
      backend_protocol = try(var.protocols[var.traffic.target.protocol], "TCP")
      backend_port     = var.traffic.target.port
      target_type      = var.service.deployment_type == "fargate" ? "ip" : "instance" # "ip" for awsvpc network, instance for host or bridge
      health_check = {
        enabled             = true
        interval            = 15 // seconds before new request
        path                = var.traffic.target.health_check_path
        port                = var.service.deployment_type == "fargate" ? var.traffic.target.port : null // traffic port by default
        healthy_threshold   = 3                                                                         // consecutive health check failures before healthy
        unhealthy_threshold = 3                                                                         // consecutive health check failures before unhealthy
        timeout             = 5                                                                         // seconds for timeout of request
        protocol            = try(var.protocols[var.traffic.target.protocol], "TCP")
        matcher             = "200-299"
      }
      protocol_version = try(var.protocol_versions[var.traffic.target.protocol_version], null)
    }
  ]

  # Sleep to give time to the ASG not to fail
  load_balancer_create_timeout = "5m"
  load_balancer_update_timeout = "5m"

  tags = var.common_tags
}

module "elb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.0.0"

  name        = "${var.common_name}-sg-elb"
  description = "Security group for ALB within VPC"
  vpc_id      = var.vpc.id

  ingress_with_cidr_blocks = [
    for listener in var.traffic.listeners : {
      from_port   = listener.port
      to_port     = listener.port
      protocol    = "tcp"
      description = "Listner port ${listener.port}"
      cidr_blocks = "0.0.0.0/0"
    } if listener.protocol == "http" || (listener.protocol == "https" && var.acm != null)
  ]
  egress_rules = ["all-all"]
  # egress_cidr_blocks = module.vpc.subnets_cidr_blocks

  tags = var.common_tags
}
