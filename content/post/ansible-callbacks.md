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



## Sources

- [Callback Plugins](https://docs.ansible.com/ansible/2.7/plugins/callback.html)

- [ansible.cfg](https://docs.ansible.com/ansible/2.7/reference_appendices/config.html#default-callback-plugin-path)

- [Developing plugins](https://docs.ansible.com/ansible/2.5/dev_guide/developing_plugins.html#callback-plugins)