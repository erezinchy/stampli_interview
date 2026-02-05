This is the complete, professional README.md tailored specifically for your interview requirements. It covers the app logic, the infrastructure details, and the CI/CD flow.

Tiny IP Web App (AWS ECS + CloudFront)
A minimal Node.js application deployed on AWS ECS (Fargate), positioned behind an Application Load Balancer (ALB) and CloudFront. The application renders a simple HTML page that displays the visitor's public IP address.

🚀 Architecture
The request flow follows this path to ensure the client IP is preserved and the application is globally performant: User → CloudFront → ALB → ECS Fargate (Node.js App)

IP Detection Logic
The application retrieves the visitor's public IP by parsing the X-Forwarded-For HTTP header.

CloudFront adds the client's IP to this header.

ALB appends its own information to the header.

The App splits the comma-separated string and takes the first value, which represents the original client.

🛠 Project Structure
app.js: Node.js Express application containing the IP logic.

Dockerfile: Container definition for the application.

package.json: Manages Node.js dependencies (Express).

terraform_arch/: Infrastructure as Code to provision AWS resources (ECR, ECS, ALB, CloudFront).

.github/workflows/deploy.yml: CI/CD pipeline for automated deployments.

.aws/task-definition.json: Task definition template used by GitHub Actions.

⚙️ CI/CD Deployment (GitHub Actions)
The deployment is fully automated via GitHub Actions on every push to the main branch:

Build & Push: The Docker image is built and pushed to Amazon ECR.

Render: The ECS Task Definition template is updated with the new image URI.

Deploy: The ECS Service is updated to deploy the new container version.

Invalidate: A CloudFront Invalidation is triggered for / to ensure the latest changes are visible.

🔑 Required GitHub Secrets
To run the deployment pipeline, configure the following secrets in your GitHub repository:

AWS_ACCESS_KEY_ID: IAM user access key.

AWS_SECRET_ACCESS_KEY: IAM user secret key.

CLOUDFRONT_DISTRIBUTION_ID: The ID of your CloudFront distribution (e.g., EOGDPVGKJ5UA8).

💻 Local Development
To run the application locally for testing:

Bash
# Install dependencies
npm install

# Start the application
node app.js
The app will be available at http://localhost:3000.

🏗 Infrastructure Details
Networking: ECS tasks are deployed in public subnets with assign_public_ip = true to allow pulling images directly from ECR.

Header Forwarding: The CloudFront distribution is configured with an Origin Request Policy (AllViewer) to ensure the X-Forwarded-For header reaches the ALB.

Health Checks: The ALB target group monitors the / (or /health) route on port 3000 to ensure task health.