module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${local.prefix}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${data.aws_region.current.name}a", "${data.aws_region.current.name}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
  
  enable_dns_hostnames = true
  enable_dns_support = true
}

######################################
# VPC Endpoint (Interface) Configuration
######################################
resource "aws_security_group" "vpce" {
  name        = "${local.prefix}-sg-vpce"
  description = "${local.prefix}-sg-vpce"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [
      # 自動化有効にすると 0.0.0.0/0
      "0.0.0.0/0"
      # module.vpc.vpc_cidr_block
    ]
  }

  tags = {
    Name = "${local.prefix}-sg-vpce"
  }
}

resource "aws_vpc_endpoint" "guardduty_data" {
  vpc_id = module.vpc.vpc_id
  vpc_endpoint_type = "Interface"
  service_name = "com.amazonaws.${data.aws_region.current.name}.guardduty-data"
  policy = templatefile("${path.module}/iam_policy_document/vpc_endpoint_gd_data.json", {
    account_id = data.aws_caller_identity.self.account_id
  })
  security_group_ids = [aws_security_group.vpce.id]
  private_dns_enabled = true
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "${local.prefix}-vpce-guardduty-data"
  }
}