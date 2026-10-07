terraform {
  backend "s3" {
    key          = "clickstream/dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
