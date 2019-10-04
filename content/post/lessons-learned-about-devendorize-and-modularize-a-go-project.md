---
title: "Lessons Learned: Devendorize and Modularize a Go Project"
date: 2019-10-02T19:26:18-07:00
tags: ["Go", "Golang", "Docker", "Go modules"]
---

```go
defer Conclusions()
```

This week I've been working on remove all the vendors of a massive Go project and make it use Go modules. It's not an easy task considering that it depends of almost 400 packages, many of such packages with different versions and using packages from Terraform and Kubernetes that are also massive consumers of external packages and provides a large amount of them.

Here are my lessons learned in the process of devendorize and modularize a Go project.

## 1. Get a backup of your vendor directory

The first step to devendorize is to remove the vendor directory after taking a backup of it, do not get rid of it, you may need it later if things goes wrong and things can go wrong very easily. Go modules are great and good for your projects but it's not completely mature yet. So, I suggest to take a backup of your precious vendors.

```bash
mv ./vendor/ /some/where/else/
```

## 2. Use a clean environment

This is a very important step. Your code may compile due to packages or modules already in your development environment. It's important to get rid of them to make sure that your code is going to compile  in your environment and the environment of other developers or contributors.

There are different ways to use or get a clean environment to work with modules:

### 2.1 Remove your packages and modules

This is an action that I recommend you do very carefully or you may be deleting your own code or version of packages that you want to keep in your computer.

First is to clean the modules. This can be done with:

```bash
go clean -modcache
```

It will erase most of the content in `$GOPATH/pkg/`. It is not recommend to delete this directory using `rm`, instead clean the mod cache and if you want it shinny then use `rm`, but to clean the mod cache is good enough.

Then delete all your packages downloaded in the pre-modules time, those that `go get` downloaded to `$GOPATH/src`. Now, this part has to be done carefully. 

Most of the time I have my code in the `$GOPATH/src` directory, for example, this blog is in `$GOPATH/src/github.com/johandry/blog`. If this is a practice that you follow I recommend to delete every directory one by one, carefully, unless you have it all in sync with your CVS (i.e. Github).

### 2.2 Use a different GOPATH

This may be the quicker way to have a clean environment but it's just temporal, so use it when you want to prove something really quick and don't want to modify your dev environment.

Define a new GOPATH variable pointing to a temporal directory. All you do after exporting the new GOPATH is isolated from your regular Go development environment. However it is not 100% isolated, you may have  environment variables or files that cause some noice.

```bash
export GOPATH=$(mktemp -d)
```

 This is going to create a temporal directory and assign GOPATH to it. Everything you do after this line, in the same shell session, will happen in this directory. So, new modules, new packages, new binaries will be there.

When you are done with your test, you can delete everything or wait for the system remove it in your next reboot.

```bash
echo $GOPATH        # make sure you are using a temporal one
go clean -modcache
rm -rf $GOPATH
```

### 2.3 Using Docker

This may be the best way to isolate a development environment, it's 100% isolated, reproducible and you can share it with your co-workers and contributors.

This is an example of a Dockerfile used to get the modules and build the application:

```dockerfile
# Base image to load all the dependencies and modules
FROM golang AS base

ENV GO111MODULE=on

WORKDIR /workspace/simple

COPY go.mod .
COPY go.sum .
RUN  go mod download

# -----------------------------------------------
# Base image for development and test the build
# Use it with `build --target=builder-dev`
FROM base AS builder-dev

ENTRYPOINT [ "bash" ]

# -----------------------------------------------
# Image to build the application
FROM base AS builder

WORKDIR /workspace/simple
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /simple 

# -----------------------------------------------
# Application image used for development and test
# Use it with `build --target=app-dev`
FROM alpine:3.9 AS app-dev

COPY --from=builder /simple /app/bin/
ENTRYPOINT [ "ash" ]

# -----------------------------------------------
# Application image, use it with `build --target=app`
FROM alpine:3.9 AS app

COPY --from=builder /simple /app/bin/
ENTRYPOINT [ "/app/bin/simple" ]
```

As you can see this Dockerfile uses multiple stages. A multi-stages Dockerfile is a very useful pattern to keep your Docker containers small, make it modular and speed up your build process. If you need more information about Dockerfiles with multiple stages I recommend reading [this article](https://docs.docker.com/develop/develop-images/multistage-build/) and other about [design patterns](https://medium.com/@tonistiigi/advanced-multi-stage-build-patterns-6f741b852fae).

In this Dockerfile are 5 stages, the first one (`base`) contain all the requirements to build the application. These requirements are Go, the Go tools and the modules the application needs. There may be other requirements such as certificates or internal modules/packages (those that are private to your company and are not in Github, for example).

The base stage begins defining all the environment variables required to build or get the modules, in this example, the variable `GO111MODULE=on` defines that we will be using Go modules.

After defining the working directory to store the entire source code of your application (i.e. `/workspace/<app_name>`) we copy into this directory the files `go.mod` and `go.sum`. These files contain all the information about the required modules. Then, we proceed to download all the packages/modules listed in `go.sum` using `go mod download` and they will be downloaded in `$GOPATH/pkg/mod/`.

In the next phase we copy all the Go source code into the image. So you may ask, why get the modules first and then the code?

Copying the `go.[mod|sum]` files and downloading the modules/packages makes Docker to create an image layer for each `COPY` directive. If one of these file changes Docker will recreate this image layer, meaning that will download the modules again but if the files do not change Docker will reuse these image layers, including the one with the modules, speeding up the process to build the application.

There are other technics to do besides downloading the modules from the `go.[mod|sum]` files. For example, get the modules into the `./vendor/` directory using `go mod vendor`. This option requires to use the flag `-mod=vendor` to build the application.

The stage `builder-dev` is used to debug the building process. Assuming something is not working downloading the modules or building the application, you can specify to Docker to stop when the `builder-dev` stage is complete. Then you can login into the container and execute the process manually or do whatever you need to debug the problem. Example:

```bash
$ docker build -t simple-builder-dev --target=builder-dev .
$ docker run --rm -it simple-builder-dev
# 
```

If needed, comment out the line with `go mod download` to debug the process and find the cause of the errors.

The `builder` stage is used to copy all the Go source code and build the application. The binary will be stored in the root directory `/`.

If you set the environment variable `DOCKER_BUILDKIT=1` Docker will build in parallel the stages that depend from the same stage, speeding up the process even more.

The last two stages are to store the binary into a container with `alpine` and the difference is that `app-dev` is used to login into the application container for testing or development purposes, while `app` is only to execute or use the application.

To get the application image just need to execute:

```bash
docker build -t simple .
docker run --rm -it simple
```

If something is wrong with your modules the process will stop in the first stage.

Keep reading to know what else you can do in this Dockerfile.

## 3. Initialize the modules

This is not new, you can read all about this in any article about Go modules. If you need more information go to the article [Using Go Modules](https://blog.golang.org/using-go-modules) from The Go Blog.

```bash
go mod init github.com/myuser/projectname
go mod tidy
```

This will create the `go.mod` file and populate it with all the modules you are using. In this process, it will also download all the used modules and create the `go.sum` file.

These 2 files (`go.[mod|sum]`) contain all the information about the required modules, like the version to download.

The `go.mod` file is the one we are going to modify (manually or with Go tools) and it has 2 important sections or directives: `require` and `replace`.

The section or directive `require` is usually generated automatically and list all the modules and the version required by the application.

The section or directive `replace` is usually added manually and it's used to modify the module parameters (name, path or version) before download it.

## 4. Update the modules list

One of the daily activities with modules is to update the list. To do this, use the command:

```bash
go mod tidy
```

Use the  `go mod tidy` command when you import a new package so it will be inserted in the `go.mod` file and this will also remove all the modules/packages that are not in use. It's important to execute `go mod tidy` after every modification to the `go.mod` file.

You can also list all the used modules and its dependencies with:

```bash
go list -m all
go list -m -versions <module>
```

To know why a module is required, use `go mod why` and it will show the shortest path from a package to the questionable package. Example:

```bash
go mod why google.golang.org/grpc
# google.golang.org/grpc
github.com/johandry/terranova-examples/aws/simple
github.com/terraform-providers/terraform-provider-aws/aws
github.com/hashicorp/terraform/helper/resource
google.golang.org/grpc
```

And recently was introduced `go mod graph` to generate the modules relationships and that can be used to visualize the modules dependencies. Example:

```bash
# require `dot` which is included in `graphviz` and requires `modgraphviz`
brew install graphviz
go install golang.org/x/exp/cmd/modgraphviz

go mod graph | modgraphviz > graph.dot
go mod graph | modgraphviz | dot -Tpng -o graph.png
open graph.png
```

But I think mod graphs are not mature yet and there will be more the near future. To know more about mod graphs read [here](https://github.com/go-modules-by-example/index/tree/master/014_mod_graph) and [here](https://github.com/go-modules-by-example/index/tree/master/018_go_list_mod_graph_why).

## 5. The Sirupsen headache 

The package `github.com/sirupsen/logrus` is a logger widely used but originally the name was `Sirupsen/logrus` (uppercase S) and when it was renamed to `sirupsen/logrus` that caused a lot of problems among all the Go developers and many headaches.

There are still some packages that use the original name or an old version of `sirupsen/logrus` that cause some conflicts with modules.

The solution to these conflicts is to add the following replace directive, however there are other solutions documented, if this solution does not work search for the different ways to solve this.

```go
replace github.com/Sirupsen/logrus => github.com/sirupsen/logrus v1.2.0
```

Or execute:

```bash
go mod edit -replace github.com/Sirupsen/logrus=github.com/sirupsen/logrus@v1.2.0
```

Why version `v1.2.0`? Well, any version higher that `v1.0.0` would work, and that's because this was the first release using the lowercase. If version `v1.2.0` cause conflicts, then try a different one higher than `v1.0.0`. Check it out in the [changelog](https://github.com/sirupsen/logrus/blob/v1.2.0/CHANGELOG.md#100).

As mentioned before, run `go mod tidy` to cleanup, update, generate the `go.sum` and download the modules.

## 6. Find the right version

Some errors are caused by using the lates and/or incorrect version of a module. To identify this situation you need to analyze the build logs. Let's see a couple of examples:

My code is using the latest version of Kubernetes so instead of using version `v1.16`, this caused the compilation error:

```bash
does not contain package k8s.io/kubernetes/pkg/kubectl/validation
```

This was fixed switching to version `v1.15` by adding to the `require` section the line `k8s.io/kubernetes v1.15.0` or executing:

```bash
go mod edit -require k8s.io/kubernetes@v1.15.0
```

Other compilation error state something similar because is using the latest version of Terraform (`v0.12.9`) but I know my code uses the version `v0.11.14`.

```bash
module github.com/hashicorp/terraform@latest (v0.12.9) found, but does not contain package github.com/hashicorp/terraform/config/module
```

So I replace it with the correct version adding this line to the `replace` section:

```go
github.com/hashicorp/terraform => github.com/hashicorp/terraform v0.11.14
```

## 7. Use the commit hash

Sometimes the version number is not easy to identify or not possible at all. In such cases try to find the last commit hash for the given tag, release, or pull request with the package version you need. 

For example, Kubernetes uses to replace the package path with a path inside the repository, so it's not possible to find the version number. Go to the repository of this package, locate the tag or release used by the Kubernetes version you need and locate the commit hash number in the right upper corner. It's better if you get the entire hash number. 

With the hash number add into the replace section the line: `<module name>[@version] => <module name> <hash number>`. For example:

```go
k8s.io/api => k8s.io/api 7cf5895f2711098d7d9527db0a4a49fb0dff7de2
```

After executing `go mod tidy` the hash will be replaced by `v0.0.0-20190620084959-7cf5895f2711` getting  this:

```go
k8s.io/api => k8s.io/api v0.0.0-20190620084959-7cf5895f2711
```

Use this method of using the commit hash as much as possible and every time you cannot find the right version number, `go mod` will try to identify the correct version number or something similar.

## 8. Read the `go.mod` of the package

During the execution of the previous step you may found a `go.mod` file, you can get advantage of this file to identify the version of the required modules.

For example, identifying the commit hash for `k8s.io/cli-runtime` I found in the `go.mod` file the module `k8s.io/client-go`. This module is also required, so use the module version and include the same line from the `require` or `replace` section into my `go.mod` file.

## 9. Private modules

Private modules are those modules that are in a GitHub Enterprise and are not available to everyone. If you have those then use the environment variable `GOPRIVATE`. For example, if my company name is acme.com then export the environment variable is like this:

```bash
export GOPRIVATE=*.acme.com
```

In the Dockerfile use it like this:

```dockerfile
ENV     GOPRIVATE=*.acme.com
```

There is other option you can do...

## 10. Keep private modules in the repo

Other option with private modules is to keep them in the repository, you can use the `./vendor/` directory for this. Then include the following line in the `replace` section of your `go.mod` file:

```go
github.acme.com/kraken/azure => ./vendor/github.acme.com/kraken/azure
```

This replace directive will use modules that are in the repository or outside of it, the path could be absolute or relative to the `go.mod` file.

As you have already figure it out, this can be used for other purpose ...

## 11. Developing/testing local modules

If it is possible to replace a module path for a local directory, then this can be used to reference local modules that I'm developing or testing or verifying some modification.

So, clone the repository of the module you are working either in the same parent directory of your repo or in an internal directory of your repo (i.e. `./internal/` or `../../foo/`), make sure you create all the directories that are in the package name and add a line like the following, assuming the `go.mod` file is in `github.acme.com/kraken/app/go.mod`.

```go
github.acme.com/kraken/azure => ./internal/github.acme.com/kraken/azure
github.acme.com/foo/aws => ../../foo/aws
github.com/bar/gcp => ../../../github.com/bar/gcp
```

## 12. Error `reading <URL>: 410 Gone`

This error happens when the `go mod` cannot get the module/package from the go modules proxy or the CVS (i.e. GitHub). To eliminate this error, use the environment variable `GONOSUMDB`. This situation is also common with private modules, so using the previous example export the environment variable like this:

```bash
export GONOSUMDB=github.acme.com/kraken
```

Using other example, use the `GONOSUMDB` in a Dockerfile like this:

```dockerfile
ENV     GONOSUMDB=github.com/terraform-providers/terraform-provider-aws
```

If there are more than one modules in this situation separate them with comma, for example:

```bash
GONOSUMDB=github.acme.com/kraken,github.com/terraform-providers/terraform-provider-aws
```

## 13. Fork and fix

This is rare scenario but it happens. 

Remember the Sirupsen headache problem? Well, there are some package that their contributors or owners forgot to maintain and fix, this is the case of `github.com/vmware/vic`. 

This package still uses `Sirupsen/logrus` so as a Good Samaritan an contributor to open source and Go community, you fork that repository, apply the fix and wait for your pull request to be merge. Meanwhile (and this can take an eternity), you have to replace that module path for your forked module. So, I added this line to the `replace` section:

```
github.com/vmware/vic => github.com/pokstad/vic v1.5.1-alpha
```

## 14. Repeat and compare

To me this sounds stupid but while I was writing this article I remove all the vendors and module files (after taking a backup of course) and repeat the entire process of modularize my project. Turns out that I got a different `go.mod`. This may be (if you do it weeks or months later) because the Go tooling was improved or some modules were improved too. Or just because I followed a different path, maybe I selected a different version for a module that required different versions of other modules and so on.

Anyways, now with multiple versions of modules I can compare them and choose the best according to my needs.

So, bottom line, you won't get the same results always modularizing your Go project. And, 

## Is devendoring really necessary?

Now you move everything into modules and you can remove the `./vendor/` directory but, is this always really necessary?

No, there are projects that use modules and still have the `./vendor/` directory. This may be have a full control of all the dependencies to avoid a malicious changes, or to make the build process easier or more stable, or because they do not care about the size of the repository. Whatever may be your reason, it is not a bad practice, **yet**.

However, you should migrate to modules and use `go mod` as your vendor or dependencies manager. So, to get the vendors in the `./vendor` directory execute:

```bash
go mod vendor
```

You can also use `go mod vendor` in the Dockerfile, however I think the process explained above is much better because Docker creates an image layer with the modules and the next `docker build` will be faster because it will reuse that layer.

Last but not least, when you use vendors, you have to use the flag `-mod=vendor` to build the application or to indicate to other Go tool that you are using vendors.

## `Conclusion()`

To migrate your Go project to modules is nowadays a very good move to do. There are some tips and good practices you should consider in the process:

1. Get a backup
2. Use a clean environment either by using a temporal GOPATH or using a Docker container
3. It may be a good idea to start from scratch by initializing your module files
4. Update your modules files periodically and during the process using `go mod tidy`.
5. Pay attention to `sirupsen/logrus` packages
6. Requires patience and experience to find the right module version. Search online for the solution or go directly into the code of the modules to identify it.
7. Don't be afraid to use the commit hash numbers, it's a good option to let `go mod` identify the right version for you.
8. Use other `go.mod` files to find the right package version
9. Use `GOPRIVATE` when you have corporate or private modules
10. Use `replace` to a local module when you are developing or testing a module
11. Use `GONOSUMDB` when there is a `410 Gone` error
12. Repeat and compare. Not all the processes to modularize a Go project lead to the same solution. You may get better results if you do it a second time. 

Evaluate the pros and cons of devendorizing your Go project, there may be good reasons to keep the `./vendor` directory in your git repo, or not.

When you are done, there is a few activities to consider:

1. Make sure the modules will work on other computers or environments. Test locally using a clean environment, ask other co-worker or contributor to review and test your code, and make sure to update your CI/CD tool to test the modules.
2. Do maintenance periodically executing `go mod tidy` and when there are changes to the code.
3. Repeat all the process when it's time to upgrade a module. 

Let us know in your comments if you have other experience, best practices or tips to share during the process of devendorizing and modularizing your Go project.