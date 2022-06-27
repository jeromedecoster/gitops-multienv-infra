module "vpc" {
  source = "../modules/vpc"

  project_name = var.project_name
  project_env  = var.project_env
  region       = var.region
}

# module "vpc" {
#   # https://github.com/terraform-aws-modules/terraform-aws-vpc
#   source  = "terraform-aws-modules/vpc/aws"
#   version = "3.14.0"

#   cidr                 = "10.0.0.0/16"
#   azs                  = data.aws_availability_zones.zones.names
#   public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
#   enable_dns_hostnames = true
#   enable_dns_support   = true

#   tags = {
#     Name = "${var.project_name}-${var.project_env}"
#   }
# }

# resource "aws_security_group" "vpc_sg" {
#   name   = "${var.project_name}-vpc-sg"
#   vpc_id = module.vpc.vpc_id

#   ingress {
#     from_port = 5432
#     to_port   = 5432
#     protocol  = "tcp"
#     # publicly accessible
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name = var.project_name
#   }
# }

