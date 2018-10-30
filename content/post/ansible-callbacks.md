---
title: "Ansible API Callback Plugin"
date: 2018-10-28T21:41:08-07:00
draft: true
---

I'm working on a new Go project that execute Ansible, this Go application has to get the Ansible output, parse it, filter it and report it in a different format. So, this is a good opportunity to use Ansible callback plugins.

Instead of let the callback plugin to send the playbook output to the consumer Go application, this plugin expose a REST and gRPC API to report the executed tasks and final statistics. All the code is available in my **[Ansible API Callback Plugin](https://github.com/johandry/ansible-api-callback-plugin)** Github repository. The development of this callback plugin is divided in three posts: the Ansible callback plugin,  the REST API using [Flask](http://flask.pocoo.org) and the gRPC API.

## Ansible Callback Plugin

When ansible executes a playbook everything that is printed out to the screen is done by an Ansible Callback plugin. For every event there is a method in the selected or default callback plugin, this method can print the state to the standard output, send it to another tool, store it in a database, or anything you want.

In the [Ansible documentation](https://docs.ansible.com/ansible/2.7/plugins/callback.html) page is explained what is a callback plugin and some examples such as [log_plays](https://docs.ansible.com/ansible/2.7/plugins/callback/log_plays.html) to send events output to a log file, [mail](https://docs.ansible.com/ansible/2.7/plugins/callback/mail.html) to report via email failed events and [osx_say](https://docs.ansible.com/ansible/2.7/plugins/callback/osx_say.html) to "speak" the events using the `say` program. [Here](https://docs.ansible.com/ansible/2.7/plugins/callback.html#plugin-list) is a full list of available plugins, you can also get the list with the command: `ansible-doc -t callback -l`

You can create your own callback plugin and enable it dropping it in the `callback_plugins` directory inside a role or in any other directory and let Ansible knows about this directory with the `callback_plugins` parameter in the `ansible.cfg` file (there could be more than one directory separated by colon).

All the custom callback plugin(s), and the available ones that are whitelisted, will be used by Ansible however, only one callback plugin can be used to manage the console output, this can be replaced with the parameter `stdout_callback` in the `ansible.cfg` file.

Example:

```ini
[defaults]
stdout_callback   = grpc
callback_plugins  = .
```

Instead of installing Ansible let's use a Docker container from `williamyeh/ansible:ubuntu16.04` or `ansible/ansible:ubuntu1604`:

```bash
docker run -it --rm --name ansible williamyeh/ansible:ubuntu16.04 ansible --version                                            
# ansible 2.5.0
#  config file = None
#  ...
#  python version = 2.7.13 (default, Nov 24 2017, 17:33:09) [GCC 6.3.0 20170516]
docker run -it --rm --name ansible williamyeh/ansible:ubuntu16.04 bash
```

And for testing, lets use a few sample roles that are simple but execute enough tasks to get some output. Check the content of the `test/` directory in [johandry/ansible-api-callback-plugin](johandry/ansible-api-callback-plugin), there is a `roles` directory with 3 roles: `go/install`, `go/build` and `service`, these roles are executed by the `playbook.yaml` file to install Go, build a simple Web service and execute it. 

The content or creation of the roles is not important here, mainly because we are doing some tasks with Ansible that shouldn't be done. It's not right to use Ansible to install Go in a Docker container, neither to build a Go program. I recommended to use multi-stages containers to build and ship the service. But if you are interested to know how to create roles, use and read about `ansible-galaxy` tool.

There is also a `docker-compose.yaml` file to make it easy the execution of the container. 

```bash
docker-compose run ansible
```

Or, to login into the container and execute the playbook manually:

```bash
docker-compose run --entrypoint /bin/bash ansible
# ansible-playbool -i inventory playbook.yaml
```

Now lets create the callback plugin

### Creating the Callback Plugin



## Sources

- [Callback Plugins](https://docs.ansible.com/ansible/2.7/plugins/callback.html)

- [ansible.cfg](https://docs.ansible.com/ansible/2.7/reference_appendices/config.html#default-callback-plugin-path)

- [Developing plugins](https://docs.ansible.com/ansible/2.5/dev_guide/developing_plugins.html#callback-plugins)
- [Docker compose file reference](https://docs.docker.com/compose/compose-file/)
- [Creating Ansible roles](https://www.azavea.com/blog/2014/10/09/creating-ansible-roles-from-scratch-part-1/)
- [Ansible-Go](https://github.com/jlund/ansible-go)
- [Microservices in Go](http://blog.johandry.com/post/intro-microservice-in-go-1/)

