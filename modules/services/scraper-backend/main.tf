# ------------
#     Backend
# ------------
module "end" {
  source = "../../components/end-http"

  vpc_id                                 = var.vpc_id
  vpc_tier                               = var.vpc_tier
  vpc_security_group_ids                 = var.vpc_security_group_ids
  common_name                            = var.common_name
  common_tags                            = var.common_tags
  account_name                           = var.account_name
  account_region                         = var.account_region
  account_id                             = var.account_id
  ecs_task_definition_image_tag          = var.ecs_task_definition_image_tag
  listener_port                          = var.listener_port
  listener_protocol                      = var.listener_protocol
  target_port                            = var.target_port
  target_protocol                        = var.target_protocol
  ecs_logs_retention_in_days             = var.ecs_logs_retention_in_days
  target_capacity_cpu                    = var.target_capacity_cpu
  capacity_provider_base                 = var.capacity_provider_base
  capacity_provider_weight_on_demand     = var.capacity_provider_weight_on_demand
  capacity_provider_weight_spot          = var.capacity_provider_weight_spot
  user_data                              = var.user_data
  protect_from_scale_in                  = var.protect_from_scale_in
  instance_type_on_demand                = var.instance_type_on_demand
  min_size_on_demand                     = var.min_size_on_demand
  max_size_on_demand                     = var.max_size_on_demand
  desired_capacity_on_demand             = var.desired_capacity_on_demand
  maximum_scaling_step_size_on_demand    = var.maximum_scaling_step_size_on_demand
  minimum_scaling_step_size_on_demand    = var.minimum_scaling_step_size_on_demand
  instance_type_spot                     = var.instance_type_spot
  min_size_spot                          = var.min_size_spot
  max_size_spot                          = var.max_size_spot
  desired_capacity_spot                  = var.desired_capacity_spot
  maximum_scaling_step_size_spot         = var.maximum_scaling_step_size_spot
  minimum_scaling_step_size_spot         = var.minimum_scaling_step_size_spot
  ecs_execution_role_name                = var.ecs_execution_role_name
  ecs_task_container_role_name           = var.ecs_task_container_role_name
  ecs_task_container_s3_env_policy_name  = var.ecs_task_container_s3_env_policy_name
  ecs_task_definition_memory             = var.ecs_task_definition_memory
  ecs_task_definition_memory_reservation = var.ecs_task_definition_memory_reservation
  ecs_task_definition_cpu                = var.ecs_task_definition_cpu
  ecs_task_desired_count                 = var.ecs_task_desired_count
  port_mapping                           = var.port_mapping
  repository_image_keep_count            = var.repository_image_keep_count
  force_destroy                          = var.force_destroy
  github_organization                    = var.github_organization
  github_repository                      = var.github_repository
  github_branch                          = var.github_branch
  github_workflow_file_name_ecr          = var.github_workflow_file_name_ecr
  github_workflow_name_ecr               = var.github_workflow_name_ecr
  github_workflow_file_name_env          = var.github_workflow_file_name_env
  github_workflow_name_env               = var.github_workflow_name_env
  github_workflow_file_name_ecs          = var.github_workflow_file_name_ecs
  github_workflow_name_ecs               = var.github_workflow_name_ecs
  bucket_env_name                        = var.bucket_env_name

  env_file_name = "production.env"
}

# ------------------------
#     MongoDB
# ------------------------
module "mongodb" {
  source = "../../data/mongodb"

  common_name            = var.common_name
  vpc_id                 = var.vpc_id
  vpc_security_group_ids = var.vpc_security_group_ids
  common_tags            = var.common_tags
  force_destroy          = var.force_destroy
  ami_id                 = var.ami_id
  instance_type          = var.instance_type
  user_data_path         = var.user_data_path
  user_data_args         = var.user_data_args
  bastion                = false
  aws_access_key         = var.aws_access_key
  aws_secret_key         = var.aws_secret_key
}
