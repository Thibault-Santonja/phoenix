# Deploying Phoenix Applications with Kamal

Deploying Phoenix applications in production environments poses unique challenges due to Elixir and the Erlang Virtual Machine (VM). The ecosystem offers multiple strategies — ranging from releases to mix-based approaches (as detailed in the Phoenix Deployment Guide) — and various platforms employ different methods. While some rely on buildpacks (for example, Heroku and Gigalixir), others use containerization (like Fly). These hosted solutions simplify deployment but often come with a premium cost.

Kamal stands out by providing a cloud-like developer experience while remaining deployable on any infrastructure, from bare metal to cloud VMs. With a focus on simplicity and convention over configuration, it streamlines Docker-based deployments. Although it originated in the Rails ecosystem, its language-agnostic approach makes it an excellent fit for Phoenix applications.

## Understanding Kamal

Launched in 2023 by Basecamp (formerly 37signals) and led by David Heinemeier Hansson (DHH), Kamal was created as a straightforward yet powerful deployment tool. Its core principles — strong defaults modeled on "convention over configuration," an intuitive CLI with clear feedback, and features such as health checks, rollbacks, and zero-downtime deployments — simplify the Docker workflow, from image building to container orchestration. This minimizes operational overhead, letting you concentrate on application development.

When compared to other tools in the Elixir ecosystem, Kamal avoids the infrastructure lock-in and premium costs of Heroku-style solutions while offering a gentler learning curve than Kubernetes. For Phoenix applications, it strikes a balance between managing distributed systems and maintaining an accessible interface that doesn't demand a dedicated DevOps team.

## Preparing Your Phoenix Application

Before deploying with Kamal, ensure your Phoenix application is containerized. You may choose to use releases or run `mix phx.server` directly within the container — both approaches require a Dockerfile to copy your source or release bundle.

For releases, run the `mix phx.gen.release --docker` task (see the [Phoenix Release Deployment Guide](https://hexdocs.pm/phoenix/releases.html#containers)); otherwise, adjust the Dockerfile from the guide as needed.

For secrets management, Kamal's integration with password managers prevents hardcoding sensitive information. With these preparations complete, your Phoenix application will be ready for deployment with Kamal, properly containerized and configured for production environments.

## Deployment Process

### Installing Kamal

After containerizing your application, set up Kamal for deployment. Since Kamal is distributed as a Ruby gem, install Ruby (using version managers like [mise-en-place](https://mise.jdx.dev/) or [asdf](https://asdf-vm.com/)) and create a Gemfile in your project's root:

```bash
bundle init
bundle add kamal
bundle install
bundle exec kamal version
```

Then initialize Kamal with:

```bash
bundle exec kamal init
```

This generates key configuration files: `config/deploy.yml` for deployment settings, `.kamal/secrets` for secret management, and `.kamal/hooks` for any custom tasks.

### Provisioning a Server

To deploy an app with Kamal, you'll need to provision a server. This could be a cloud server (for example, from Hetzner or a Digital Ocean droplet), a bare-metal server, or even a computer on your local network. The only requirement is that it be configured with vanilla Ubuntu and your development machine can SSH to it.

To enable SSH access to the server, copy your SSH public key to `~/.ssh/authorized_keys` on the server. If you need to generate a key, you can do that with:

```bash
ssh-keygen -t ed25519
```

### Kamal Configuration

The `config/deploy.yml` file defines the deployment setup: the servers' IPs, container settings, and environment variables.

For example:

```yaml
# Name of your application. Used to uniquely configure containers.
service: my-app
```

The next part is the container image name. This will be used to upload the image to a container registry, so you'll need something that the registry understands. For example, if you are uploading to the GitHub Container Registry, the image name will be `<<org-name>>/<<app-name>>`.

```yaml
# Name of the container image.
image: my-user/my-app
```

Next, we define the servers the app should be deployed to. If you are only deploying the web server, the `servers` key will contain a single entry (the `web` role). For complex apps (e.g., ones that run background workers), it is possible to start multiple containers per app — either on the same server or different servers. Additionally, it is also possible to deploy the same role to multiple servers (for example, when you want multiple web servers behind a load balancer).

We'll see the advanced options available in the next post. For now, let's focus on a single `web` server setup. We'll need to add the IP of the server we provisioned in the configuration file of the previous step.

```yaml
# Deploy to these servers.
servers:
  web:
    - 192.168.0.1
  # job:
  #   hosts:
  #     - 192.168.0.1
  #   cmd: bin/jobs
```

Next, we configure the proxy. Kamal comes with a built-in proxy: the public-facing part of your server, which then forwards all incoming requests to the respective server. The proxy is capable of handling SSL termination and automatic SSL certificate provisioning via [Let's Encrypt](https://letsencrypt.org/).

```yaml
# Enable SSL auto certification via Let's Encrypt.
proxy:
  ssl: true
  host: app.example.com
  # Proxy connects to your container on port 80 by default.
  # app_port: 3000
```

Next, we configure the container registry that Kamal uses. The container registry is where all built images will be uploaded to and then pulled on the servers. The default is Docker Hub, but many others are supported using the `server` configuration.

```yaml
# Credentials for your image host.
registry:
  # Specify the registry server, if you're not using Docker Hub
  # server: registry.digitalocean.com / ghcr.io / ...
  username: my-user
  password:
    - KAMAL_REGISTRY_PASSWORD
```

Then, we configure the builder that builds the image from the Dockerfile. We can mostly leave our app as-is: the defaults are quite sufficient.

```yaml
# Configure builder setup.
builder:
  arch: amd64
  # args: ...
```

Now let's inject environment variables into the containers. Kamal handles them in two stages: `clear` and `secret`. Clear variables have a value defined inline in the configuration file. The secrets, on the other hand, only have a name inside the configuration file. Kamal uses `.kamal/secrets` to read the variable's name and injects it into the containers. We'll learn more about them in the secrets management section of this post.

```yaml
# Inject ENV variables into containers (secrets come from .kamal/secrets).
#
# env:
#   clear:
#     DB_HOST: 192.168.0.2
#   secret:
#     - RAILS_MASTER_KEY
```

There are also several other advanced configuration options that we'll explore later on in this and the next post.

### Managing Secrets

Kamal uses the `.kamal/secrets` file to expose sensitive data to containers. A typical structure is:

```bash
SECRETS=$(kamal secrets fetch ...)
REGISTRY_PASSWORD=$(kamal secrets extract REGISTRY_PASSWORD $SECRETS)
DB_PASSWORD=$(kamal secrets extract DB_PASSWORD $SECRETS)
```

`kamal secrets fetch` [supports several adapters](https://kamal-deploy.org/docs/commands/secrets/) including 1Password, LastPass, Bitwarden, among others.

If you don't want to use a secrets manager, it is also possible to expose environment variables as secrets by accessing the environment variable using `$NAME` inside `secrets`. For example, the below example exposes a secret named `REGISTRY_PASSWORD` with the value `$KAMAL_REGISTRY_PASSWORD` (the value of the environment variable named `KAMAL_REGISTRY_PASSWORD`):

```bash
REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
```

### Server Bootstrap

If this is the first time you are deploying to a server with Kamal, you'll need to install some tools on the server. Kamal makes this easy through the [kamal server bootstrap](https://kamal-deploy.org/docs/commands/server/) command.

Once `config/deploy.yml` is ready, just run the bootstrap command: it will install Docker and set up your server to host deployments from Kamal.

### Deploying Your Phoenix Application

Now that we know the anatomy of the Kamal configuration and secrets files and our server is ready to handle deployments, let's get back to deploying our application.

A basic Phoenix application mostly needs two secrets: `SECRET_KEY_BASE` and `DATABASE_URL`. Depending on your use case, you might need more, but Kamal makes it easy to define and expose as many environment variables as you like. We'll additionally need a password to access the container registry.

The simplest way to expose them to your app is through environment-level secrets. Generate and export the secrets as environment variables.

```bash
$ mix phx.gen.secret
REALLY_LONG_SECRET
$ export SECRET_KEY_BASE=REALLY_LONG_SECRET
$ export DATABASE_URL=ecto://USER:PASS@HOST/database
$ export KAMAL_REGISTRY_PASSWORD=SOME_REGISTRY_PASSWORD_OR_ACCESS_TOKEN
```

Then update `.kamal/secrets` accordingly:

```bash
SECRET_KEY_BASE=$SECRET_KEY_BASE
DATABASE_URL=$DATABASE_URL
REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
```

Here's a [minimal deploy.yml](https://gist.github.com/sapandiwakar/c99e555ed45f293c7b6b3edcd1dfec40) that makes use of these variables to deploy the application.

### All Systems Go!

Finally, we are there! We can deploy the app with a [single command](https://kamal-deploy.org/docs/commands/deploy/):

```bash
kamal deploy
```

This builds the app, pushes it to the registry, and deploys it on our servers. The deployment takes place in a secondary container which goes live only after all health checks pass. If any step of the process fails, the previous app container keeps actively serving all traffic without any interruptions.

### Accessing Remote Console

One of the great features of Kamal for Phoenix applications is the ability to access your IEX console in production. You can do this with:

```bash
bundle exec kamal app exec --interactive --reuse "/app/bin/my_app remote"
```

This can be hard to remember, which is where Kamal aliases come in. Inside the `deploy.yml` file, an `aliases` entry can be used to define custom commands:

```yaml
aliases:
  console: app exec --interactive --reuse "/app/bin/my_app remote"
  shell: app exec --interactive --reuse "/bin/sh"
  logs: app logs -f
```

With this in the config, we get three new commands that can be run from the app folder (on the local/developer machine):

```bash
kamal console  # Access iex console on the server
kamal shell    # Access the shell prompt on the server
kamal logs     # Starts tailing application logs from the server
```

Now let's turn to some more advanced configurations we can do in Phoenix.

## Advanced Phoenix-Specific Configurations

We can make our configuration more advanced by automating database migrations and through GitHub Actions / CI/CD pipelines. Let's look at automating migrations first.

### Automating Database Migrations with Kamal

Database migrations are one of the most common requirements when deploying applications. With Phoenix, you typically need to run `mix ecto.migrate` before your application starts serving traffic. While Kamal doesn't have built-in support specifically for Phoenix migrations, we can leverage Docker's entrypoint mechanism to automate this process.

We can create a custom Docker entrypoint script that runs migrations before starting your application. First, create a file called `docker-entrypoint` in your project's `config` directory:

```bash
#!/bin/sh -e

# If running the server, run migrations first
if [ "$#" -eq 1 ] && [ "$1" = "/app/bin/server" ]; then
  echo "Running migrations before starting server..."
  /app/bin/migrate
  echo "Migrations completed!"
fi

# Execute the original command
exec "${@}"
```

This uses the [migrate script generated when you bundle the app with mix release](https://hexdocs.pm/phoenix/releases.html#ecto-migrations-and-custom-commands). If you are using regular `mix` commands to run the app, replace them with `mix ecto.migrate`.

Then update your Dockerfile to use this entrypoint script. In the final stage of your Dockerfile, add:

```dockerfile
# Set the entrypoint and default command
ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["/app/bin/server"]
```

With this setup, whenever Kamal deploys your application, the Docker container will:

1. Execute the entrypoint script.
2. The script detects the server starting.
3. The script runs migrations first.
4. Then it starts your Phoenix application.

This approach ensures that your database is always up to date before your application starts handling requests. It's particularly valuable in Kamal's zero-downtime deployment process, as the new version of your application will only receive traffic after migrations have successfully completed.

### Integration with GitHub Actions or CI/CD Pipelines

The final step in creating a truly modern deployment workflow is to integrate Kamal with your CI/CD pipeline. This integration brings you closest to the convenience of Platform as a Service (PaaS) offerings like Heroku or Fly, allowing your team to focus on writing code while deployments happen automatically in the background.

With CI/CD integration, you can automatically deploy when changes are merged to your main branch (optionally after your tests and linting processes pass to ensure quality). This also creates a consistent, reproducible deployment process.

GitHub Actions provides a straightforward way to implement this workflow. There are many ways to provide your apps with access to secrets during deployment. The easiest is to store your deployment secrets in GitHub's repository secrets. For our dummy app, this includes:

- `SECRET_KEY_BASE`: Your Phoenix application's secret key
- `DATABASE_URL`: Connection string for your database
- `KAMAL_REGISTRY_PASSWORD`: Password or token for your Docker registry
- `SSH_PRIVATE_KEY`: SSH key for accessing your deployment servers

Then, create a workflow file at `.github/workflows/ci.yml` with the following content:

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  test:
    # Your existing test job
    runs-on: ubuntu-latest
    # ...

  lint:
    # Your existing lint job
    runs-on: ubuntu-latest
    # ...

  deploy:
    needs: [test, lint]
    runs-on: ubuntu-latest
    if: ${{ github.event_name == 'push' && github.ref_name == 'main' }}
    timeout-minutes: 20
    env:
      DOCKER_BUILDKIT: 1
      VERSION: ${{ github.sha }}
      SECRET_KEY_BASE: ${{ secrets.SECRET_KEY_BASE }}
      DATABASE_URL: ${{ secrets.DATABASE_URL }}
      KAMAL_REGISTRY_PASSWORD: ${{ secrets.KAMAL_REGISTRY_PASSWORD }}

    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        id: buildx
        uses: docker/setup-buildx-action@v3

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - name: Setup SSH
        uses: webfactory/ssh-agent@v0.9.1
        with:
          ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}

      - name: Deploy
        run: bundle exec kamal deploy --version=$VERSION
```

This workflow does the following:

1. Runs on every push to the main branch.
2. Waits for tests and linting to pass before deploying.
3. Sets up all necessary tools (such as Docker, Ruby, and SSH).
4. Passes your secrets as environment variables to Kamal.
5. Deploys using the Git commit SHA as the version tag.

The `--version=$VERSION` flag tells Kamal to tag your Docker image with the Git commit SHA, making each deployment uniquely identifiable and traceable back to a specific commit.

There are several alternatives for managing secrets in this workflow:

- **Environment Variables** (shown above): The simplest approach, which uses GitHub secrets directly.
- **1Password Integration**: If you use 1Password for team secret management, you can update the workflow to install 1Password CLI and modify your `.kamal/secrets` file to fetch from 1Password.
- **Other Secret Managers**: You can adapt the workflow to use Bitwarden, LastPass, or other supported secret managers.

For larger teams, you might also want to consider setting up staging and production environments with separate workflows triggered by different branches or using GitHub environments for more controlled deployments.

With this CI/CD integration, your development workflow becomes the following:

1. Develop features in branches.
2. Open pull requests for review.
3. Merge approved pull requests to main.
4. GitHub Actions automatically tests, builds, and deploys your application.

This fully automated pipeline gives you all the convenience of a PaaS while maintaining complete control over your infrastructure and deployment process — the best of both worlds.

## Wrapping Up

Whether you're deploying a simple Phoenix application or a complex distributed system, Kamal provides a solid foundation that grows with your needs. By following the steps outlined in this article, you'll have a modern, efficient deployment workflow that lets you concentrate on what matters most: building great applications with Elixir and Phoenix.

For those interested in exploring further, here are some topics to consider:

- **Multi-Role Deployments**: Set up separate web and background worker containers using Kamal's multi-role support.
- **Elixir Clustering**: Configure distributed Erlang clusters across multiple containers using `libcluster`.
- **Advanced Monitoring**: Integrate with application performance monitoring tools like [AppSignal for comprehensive monitoring of your Phoenix applications](https://www.appsignal.com/elixir).
- **Automated Scaling**: Implement horizontal scaling strategies for handling traffic spikes.
- **Backup and Disaster Recovery**: Establish robust backup procedures for your databases and application state.

We will discuss some of these topics in the next part of this series. Until then, happy coding!

---

*Source: [AppSignal Blog](https://blog.appsignal.com/2025/06/10/deploying-phoenix-applications-with-kamal.html)*
