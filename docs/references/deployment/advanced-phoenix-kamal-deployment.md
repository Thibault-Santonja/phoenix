# Advanced Strategies to Deploy Phoenix Applications with Kamal

In the first part of our series, we explored how Kamal simplifies Docker-based deployments while providing a cloud-like developer experience. We covered the basics of containerizing Phoenix applications, configuring Kamal, managing secrets, and implementing a CI/CD pipeline for automated deployments.

Now that we've established a solid foundation for deploying Phoenix applications, it's time to dive deeper into more advanced deployment scenarios that leverage both Kamal's flexibility and the Elixir ecosystem's robust distributed capabilities. These strategies will help you scale your Phoenix applications beyond a single instance and build resilient, production-grade systems.

The Erlang VM (BEAM) was designed from the ground up for building fault-tolerant, distributed systems. When combined with Kamal's multi-role deployment capabilities, we can create sophisticated architectures that maximize the strengths of both technologies. Whether you're running background processing with dedicated worker containers, setting up clustered Elixir nodes, or implementing zero-downtime scaling strategies, Kamal provides the infrastructure orchestration layer while Phoenix and the BEAM provide the application resilience.

In this second part, we'll explore how to:

- Configure multi-role deployments to separate web servers from background workers
- Establish Elixir clustering across containers for distributed Phoenix applications
- Implement advanced monitoring solutions for production visibility

By the end of this article, you'll know how to deploy complex Phoenix applications that can scale horizontally while maintaining the operational simplicity that Kamal offers.

Let's begin by extending our basic deployment to handle multiple roles and establish communication between them.

## Multi-Role Deployments with Kamal

One of the most common requirements for growing Phoenix applications is the need to separate concerns between web servers and background workers. This separation allows you to:

- Scale web servers and background jobs independently based on their specific resource needs
- Isolate potentially resource-intensive background tasks from affecting web request performance
- Implement different deployment strategies for each component of your application

Kamal makes this separation straightforward through its multi-role deployment configuration. Let's expand our deployment setup to include dedicated worker containers.

### Configuring Worker Roles in Kamal

A web role is responsible for handling user-facing requests — this is your Phoenix Server. A worker role can, for example, be responsible for running background jobs such as sending emails or processing data. There is no limit to what roles you can define with Kamal. However, `web` is a special role that receives requests from kamal proxy if it is enabled.

Let us update our `deploy.yml` file to define both web and worker roles:

```yaml
service: my-app
image: my-user/my-app

servers:
  web:
    hosts:
      - 123.456.789.10  # Your web server IP
  
  worker:
    hosts:
      # Can be same or different server
      - 123.456.789.10
    # Containers can pass custom environment variables - these will be merged
    # with the common env vars
    env:
      clear:
        ROLE: WORKER
    # Containers can run a different command
    # cmd: /app/bin/my_app worker

# Common configuration for all roles
env:
  secret:
    - SECRET_KEY_BASE
    - DATABASE_URL
```

This configuration introduces several important concepts. We define both `web` and `worker` roles, each with its own servers and commands. Each role starts a separate container with the possibility of overriding the command or environment for that container. Using the `env` configuration inside the role, we can provide different environment variables for different roles.

Note that Kamal expects there to be a `web` role (which is the default if you skip the role label and just define the IPs inside the server configuration). You can set a different `primary_role` in the root configuration.

### Modifying Your Phoenix Application for Worker Processes

To take advantage of this multi-role setup, your Phoenix application needs a way to start different processes based on the container's role. This depends largely on what background worker strategy you are using. Let's see an example using the popular background jobs engine [Oban](https://github.com/oban-bg/oban).

In this code, we first read the `ROLE` environment variable to determine the container's role. If the `ROLE` is "WEB", we start the Phoenix Endpoint to handle HTTP requests and an Oban server without any queues. If the `ROLE` is "WORKER", we don't start the Phoenix Endpoint. Instead, we start an Oban server with the default configuration to process background jobs.

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    role = System.get_env("ROLE", "WEB")
    
    children =
      get_children_for_role(role)
      |> Enum.filter(& &1)

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp common_children() do
    # Common components for all roles
    [
      MyApp.Repo,
      MyApp.JobRepo,
      {Phoenix.PubSub, name: MyApp.PubSub},
      {Cluster.Supervisor, [
        Application.get_env(:libcluster, :topologies, []),
        [name: MyApp.ClusterSupervisor]
      ]}
    ]
  end

  defp get_children_for_role("WEB") do
    oban_config_without_queues =
      Application.fetch_env!(:my_app, Oban)
      |> Keyword.merge(queues: [], plugins: [])

    common_children() ++ [
      MyAppWeb.Endpoint,
      {Oban, oban_config_without_queues}
    ]
  end

  defp get_children_for_role("WORKER") do
    common_children() ++ [
      {Oban, Application.fetch_env!(:my_app, Oban)}
    ]
  end
end
```

With this structure, your application will start different components based on the container's role:

- Web containers will start the Phoenix Endpoint to handle HTTP requests. They will start an Oban server with no queues, so you can call `Oban.insert` to enqueue background jobs, but those jobs won't be processed.
- Worker containers will not start Phoenix Endpoint but instead start `Oban` with default configuration (you'll have this in `config/config.exs` or similar) to handle background jobs.

This approach allows you to share code between roles while maintaining separation of concerns at runtime.

### Deploying Multi-Role Applications

With this configuration in place, deploying becomes just as simple as before:

```bash
bundle exec kamal deploy
```

Kamal will automatically deploy both web and worker containers according to the configuration. You can also target specific roles for deployment:

```bash
bundle exec kamal deploy --roles=web     # Deploy only web servers
bundle exec kamal deploy --roles=worker  # Deploy only workers
```

This granular control is especially useful for making role-specific changes without disrupting your entire application.

## Elixir Clustering Across Containers

One of Elixir's greatest strengths is its ability to run as a distributed system across multiple nodes. A node is an instance of the Erlang VM running your application. For example, in the above configuration, we started one web server and one worker — each of these is a separate node. While they can work fine in isolation, clustering allows them to coordinate better.

For example, clustering makes global process registration possible, so any node can locate and communicate with a specific process running elsewhere in the cluster. In case of failure, supervision trees can restart processes on different nodes, improving fault tolerance. Clustering also enables distributed task queues, shared ETS/Mnesia tables, and the ability to broadcast events across all nodes — essential for real-time features in modern applications.

When deploying with Kamal, we can take advantage of this capability to create resilient clusters that span multiple containers and even multiple physical servers.

### Setting Up libcluster for Container Discovery

The [libcluster](https://github.com/bitwalker/libcluster) library provides strategies for automatic node discovery and connection. For deployments spanning a single node, we'll use the `Cluster.Strategy.Gossip` strategy, which works well in containerized environments.

First, add `libcluster` to your dependencies:

```elixir
# mix.exs
defp deps do
  [
    # ...existing deps...
    {:libcluster, "~> 3.5"}
  ]
end
```

Next, configure `libcluster` in your application supervision tree:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  defp common_children() do
    [
      {Cluster.Supervisor, [libcluster_topologies(), [name: MyApp.ClusterSupervisor]]},
      # ...existing children...
    ]
  end

  defp libcluster_topologies() do
    # When using releases, this can come from config/runtime.exs using Application.get_env/2
    [
      gossip: [
        strategy: Cluster.Strategy.Gossip,
        config: [
          multicast_addr: System.get_env("CLUSTER_MULTICAST_ADDRESS", "233.252.1.32"),
          port: System.get_env("CLUSTER_PORT", "45892") |> String.to_integer()
        ]
      ]
    ]
  end
end
```

### Creating a Distribution Configuration for Release

If you're using Elixir releases (which is recommended for production), you'll need to properly configure distribution settings in your release configuration:

```bash
# rel/env.sh.eex
#!/bin/sh

# Set the release distribution to work on the same node and not require FQDN
export RELEASE_DISTRIBUTION=sname
```

### Updating Kamal Configuration for Node Communication

For containers to communicate properly in a cluster, we need to ensure two things:

1. **The nodes have the same value for the `RELEASE_COOKIE` environment variable.**

You can use any of the methods discussed in Part 1 of this post to expose this variable. Just make sure that you add it to your environment secrets inside `config/deploy.yml`:

```yaml
# config/deploy.yml
# ...existing configuration...
env:
  secrets:
    - RELEASE_COOKIE
    # ...other secrets...
```

2. **The nodes can reach each other.**

For this, we don't need to configure anything as long as the containers are on the same node. This is because Kamal automatically creates a Docker network that all nodes join and can communicate with each other.

Once the nodes join the same cluster, you'll unlock a host of benefits that come with it. For example:

- If you use `Phoenix.PubSub` with the `PG2` adapter (which is the default), you'll see that PubSub messages are now delivered automatically across nodes. That means you can broadcast from a background job and subscribe to that event inside a LiveView.
- Communicate with processes on other nodes simply like you would do if they were on the same node. OTP handles everything else at the BEAM level once the nodes are clustered — no need for Redis, Kafka, or other synchronization tools or message brokers.

### Clustering Containers Across Different Nodes

As you've probably already guessed, the `Gossip` strategy only works across containers on a single node. But that doesn't mean that you'll have to constrain clustered deployments to a single node. We can use other `libcluster` topologies to enable clustering across nodes, but it'll just need a little more work.

Let's start by configuring `libcluster` to use the [libcluster_postgres](https://github.com/supabase/libcluster_postgres) strategy. This strategy uses a shared PostgreSQL database to store a list of nodes in the cluster. All nodes listen for and send notifications to a shared Postgres channel. When a node comes online, it begins to broadcast its name in a "heartbeat" message to the channel. All other nodes that receive this message attempt to connect to it.

```elixir
# config/runtime.exs
# Libcluster is using Postgres for Node discovery
# The library only accepts keyword configs, so the DATABASE_URL has to be
# parsed and put together with the ssl pieces from above.
postgres_config = Ecto.Repo.Supervisor.parse_url(System.fetch_env!("DATABASE_URL"))

libcluster_db_config =
  [port: 5432]
  |> Keyword.merge(postgres_config)
  |> Keyword.take([:hostname, :username, :password, :database, :port])
  |> Keyword.merge(ssl: System.get_env("DATABASE_SSL", "true") == "true")
  |> Keyword.merge(ssl_opts: [cacerts: :public_key.cacerts_get()])
  |> Keyword.merge(parameters: [])
  |> Keyword.merge(channel_name: "my_app_clustering")

config :libcluster,
  topologies: [
    postgres: [
      strategy: LibclusterPostgres.Strategy,
      config: libcluster_db_config
    ]
  ]
```

The next part is ensuring that the containers can communicate with each other across nodes. Unfortunately, Kamal doesn't (yet) allow exposing custom ports from the servers over the public network.

To enable nodes to connect to each other, Erlang uses a small service called The Erlang Port Mapper Daemon (epmd). It runs on each machine and acts as a name server, mapping node names to their corresponding IP addresses and ports.

So to allow clustering across physical nodes, we'll need to start a separate accessory and proxy the [epmd](https://www.erlang.org/docs/26/man/epmd) requests to the application servers through that proxy.

First, configure a `Traefik` proxy as a Kamal accessory inside the configuration.

```yaml
# config/deploy.yml
accessories:
  traefik:
    service: traefik
    image: traefik:v3.1
    options:
      publish:
        - "6789:6789"
    cmd: "--providers.docker --providers.docker.exposedByDefault=false --entryPoints.epmd.address=:6789 --log.level=INFO"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
```

To start it, simply run:

```bash
bundle exec kamal accessory boot traefik
```

This will start the accessory on all servers defined in your configuration.

We can use Traefik's labeling system to label our containers so that it forwards all TCP traffic received on the epmd port 6789 on the host to port 6789 of the container. This way, we start a Traefik proxy on each server to forward epmd requests to the application containers. Each node uses the `libcluster_postgres` strategy to discover nodes in the cluster. Once `libcluster` is able to discover nodes and epmd is accessible across all nodes, Erlang is able to establish a cluster.

```yaml
servers:
  web:
    hosts:
      - 1.2.3.4
    env:
      clear:
        RELEASE_NODE: my_app_web@1.2.3.4
    labels:
      traefik.enable: true
      traefik.tcp.routers.epmd.rule: "ClientIP(`0.0.0.0/0`)"
      traefik.tcp.routers.epmd.priority: 5
      traefik.tcp.routers.epmd.entryPoints: epmd
      traefik.tcp.routers.epmd.service: epmd
      traefik.tcp.services.epmd.loadBalancer.server.port: 6789
```

The deployment steps don't change. All you need is still only a single command to deploy your apps:

```bash
bundle exec kamal deploy
```

## Advanced Monitoring Solutions

In a production environment, visibility into your application's performance and health is crucial. While Kamal makes deployments easy, it's very important to keep monitoring your app for any problems that might occur.

AppSignal provides comprehensive monitoring for [Elixir and Phoenix applications](https://www.appsignal.com/elixir). Setting it up with your Kamal deployment is straightforward.

First, add AppSignal to your dependencies:

```elixir
# mix.exs
defp deps do
  [
    # ...existing deps...
    {:appsignal_phoenix, "~> 2.0"}
  ]
end
```

Install it inside the app with:

```bash
mix appsignal.install YOUR_PUSH_API_KEY
```

Update your Kamal configuration to inject the AppSignal push API key as a secret:

```yaml
# config/deploy.yml
# ...existing configuration...
env:
  clear:
    APPSIGNAL_APP_ENV: "production"
  secret:
    - DATABASE_URL
    - APPSIGNAL_PUSH_API_KEY
```

[Check out our full guide to integrate AppSignal into Phoenix](https://docs.appsignal.com/elixir/integrations/phoenix.html).

### Logging and Log Management

In addition to application monitoring, AppSignal also makes it easy to store application logs for debugging issues. Once the AppSignal SDK is integrated, we can configure the Erlang `:logger` to use the `Appsignal.Logger.Handler` module as a handler, by calling the `Appsignal.Logger.Handler.add/2` function in your `Application.start/2` callback:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Appsignal.Logger.Handler.add("phoenix")
    # start supervisor and other config...
  end
end
```

## Scaling Strategies

As your application grows, you'll need to scale horizontally to handle increased traffic. Kamal only supports manual scaling out of the box. To scale, manually adjust your deployment configuration:

```yaml
# config/deploy.yml
servers:
  web:
    hosts:
      - 123.456.789.10
      - 123.456.789.11
      - 123.456.789.12
  worker:
    hosts:
      - 123.456.789.10
```

This configuration deploys:

- 3 web containers (1 per server)
- 1 worker container

To scale up, you simply update the configuration and redeploy (with `bundle exec kamal deploy`).

While this might look like a downside compared to most cloud service offerings that provide some form of auto-scaling during peak loads, it is important to note that Kamal does not maintain a running daemon. It manages deployments on a push-based model (where updates are pushed to the server on deployments), so auto-scaling is impossible. To deal with this, Kamal advocates over-provisioning for the spikes since the baseline cost (moving from cloud providers to self-hosted servers or budget providers like Hetzner) is several times lower.

## Wrapping Up

In this comprehensive guide to advanced Phoenix deployment with Kamal, we've explored how to leverage both technologies to build resilient production systems. By implementing multi-role deployments, Elixir clustering, and advanced monitoring, you now have the tools to deploy even the most complex Phoenix applications with confidence.

The combination of Phoenix's distributed capabilities and Kamal's simple yet powerful deployment model gives you the best of both worlds: the resilience and scalability of the Erlang VM with the operational simplicity of modern containerized deployments.

As you continue to evolve your deployment strategy, remember that simplicity and automation are key. Each enhancement to your deployment process should make your life easier, not more complex. With Kamal and Phoenix, you have the foundation to build systems that scale seamlessly while remaining manageable for small teams.

Happy deploying!

---

*Source: [AppSignal Blog](https://blog.appsignal.com/2025/07/08/advanced-strategies-to-deploy-phoenix-applications-with-kamal.html)*
