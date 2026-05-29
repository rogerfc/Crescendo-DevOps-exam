# DevOps Technical Exam

Stack: AWS, Terraform, GitHub Actions, Nginx, Tomcat, Magnolia CMS

Time: Aim for under a day. We're looking at your approach, not perfection or completeness. We want to see Magnolia stand up with a solid approach, not see you waste your time.

## The Task
Use Terraform to deploy Magnolia CMS onto AWS, fronted by an ALB and CloudFront. Document everything in a clear README with an architecture diagram.

## Requirements
Feel free to adjust your approach. Our main goal is to see Magnolia running in AWS and how you would keep moving forward in a real project.

### Repository
- Create a public GitHub repo named `Crescendo-DevOps-exam` and add `tristanamargo-crescendo` and `jeremysummers` as collaborators.

### Infrastructure (Terraform)
- VPC with 2 public + 2 private subnets across different AZs
- Internet Gateway, NAT Gateway, route tables
- 1 EC2 instance in a private subnet
- Application Load Balancer with target group attached to the EC2
- CloudFront distribution with the ALB as origin

### Application (auto-provisioned via Terraform)
- Tomcat + Magnolia CMS Community Edition [(install docs)](https://docs.magnolia-cms.com/product-docs/6.2/getting-started-with-magnolia/installing-magnolia/)
- Nginx reverse-proxying to Magnolia
- Reachable end-to-end via the CloudFront URL

### CI
- A GitHub Actions workflow that runs `terraform fmt`, `validate`, and `plan` on PR.

### README
- Architecture diagram (draw.io, Mermaid, hand-drawn — whatever works)
- How to run it (prerequisites, commands, required secrets)
- Assumptions and known limitations

## Submission
- Link to the repo
- Screenshots or a short video showing Magnolia loading via the CloudFront URL
- A live walkthrough of your solution with our team. Let us know when you are ready and we will get a meeting setup.

## What We're Evaluating
- Code quality and organization
- Architectural reasoning
- Clarity of documentation

