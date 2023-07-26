data "aws_region" "current" {}

locals {
  region_name = data.aws_region.current.name
  name        = join("-", [for level in var.levels : level.value])
}

module "user" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-user"
  version = "5.28.0"

  name          = join("-", [local.name, var.name])
  force_destroy = var.force_destroy

  create_iam_access_key = true

  password_length         = var.pw_length
  password_reset_required = false

  tags = var.tags
}

# # need to use AWS 
# resource "aws_iam_virtual_mfa_device" "this" {
#   virtual_mfa_device_name = "device"
#   # path                    = "/"
#   tags = var.tags
# }

# #------------------
# #     Accounts
# #------------------
# module "account" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-account"
#   version = "5.28.0"

#   account_alias = lower(module.user.iam_user_name)

#   minimum_password_length      = var.pw_length
#   require_lowercase_characters = true
#   require_uppercase_characters = true
#   require_numbers              = true
#   require_symbols              = true
# }

locals {
  # AccountId = module.account.caller_identity_account_id
  tags = merge(var.tags, { AccountName = var.name })
}

#---------------
#     Secrets
#---------------
module "secret_manager" {
  source = "../../secret/manager"

  for_each = var.store_secrets ? { "${var.name}" = { user = module.user } } : {}
  # account = module.account

  name = join("/", concat([for level in var.levels : "${level.key}/${level.value}"], ["user/${each.value.user.iam_user_name}"]))
  secrets = [
    { key = "AWS_SECRET_KEY", value = sensitive(each.value.user.iam_access_key_secret) },
    { key = "AWS_ACCESS_KEY", value = each.value.user.iam_access_key_id },
    { key = "AWS_REGION_NAME", value = local.region_name },
    { key = "AWS_PROFILE_NAME", value = each.value.user.iam_user_name },
    { key = "AWS_USER_ID", value = each.value.user.iam_user_unique_id },
    # { key = "AWS_ACCOUNT_ID", value = each.value.account.caller_identity_account_id },
    { key = "AWS_PROFILE_ALIAS", value = each.value.user.iam_user_name },
    { key = "AWS_ACCOUNT_PASSWORD", value = each.value.user.iam_user_login_profile_password },
  ]

  tags = local.tags
}
