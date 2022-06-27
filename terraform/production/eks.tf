module "eks" {
  source = "../modules/eks"

  project_name = var.project_name
  project_env  = var.project_env
  region       = var.region

  vpc_id              = module.vpc.vpc_id
  vpc_private_subnets = module.vpc.private_subnets
}
