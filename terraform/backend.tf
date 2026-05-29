terraform {
  backend "s3" {
    bucket       = "rfirpo-crescendo-tfstate"
    key          = "crescendo-devops-exam/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
    encrypt      = true
  }
}
