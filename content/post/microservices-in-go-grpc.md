---
title: "Introduction to Microservices in Go: Grpc"
date: 2019-05-26T08:39:00-07:00
tags: ["Golang", "Microservices", "gRPC", "Docker"]
draft: true
---



In this [previous post](http://blog.johandry.com/post/intro-microservice-in-go-1/) was explained how to create a REST/HTTP microservice using Go and Docker, now we'll  create a microservice using gRPC.

There are several advantages of gRPC over REST. There are many articles explaining in detail all of them so I'm going to name a few:

- gRPC is smaller and faster than REST. gRPC uses protobuf a binary that is smaller than a plain text JSON. The disadvantage is that REST is more easier to debug and visualize.
- gRPC has lower latency than REST because it uses HTTP/2, unless you use HTTP/2 with a REST API but ussualy is HTTP/1.1
- gRPC is bidirectional and async, REST instead works with request from the client to the server.
- gRPC suport streams and REST only supports requests and responses opening a TCP connection for each one.
- gRPC is API oriented, you implements the API verbs you need in a free way. REST instead is CRUD oriented, the verbs to implement are only Create/Post, Retreive/Get, Update/Put and Delete.
- gRPC protobuf generates the code in many languages, this cannot be done with pure REST, you need to use OpenAPI or Swagger.

Despite all these advantages over REST, it has one that beat gRPC: The current browsers support to gRPC is not mature yet, making it hard for users to interact with a gRPC API.  

gRPC is better used for internal communications, communication between microservices, but this does not mean that implementing gRPC is to resign to REST. It is possible to expose a REST API and the gRPC API thanks to the [gRPC gateway](https://github.com/grpc-ecosystem/grpc-gateway) and [gRPC-Web](https://github.com/grpc/grpc-web).

Having gRPC and REST APIs to expose, there are 4 options to consider: just REST (explained in the [previous blog post](http://blog.johandry.com/post/intro-microservice-in-go-1/)), <u>just gRPC</u>, <u>REST and gRPC</u> each one on its own endpoint (or port), and the last one is <u>gRPC and REST exposed in one single endpoint</u>. Lets get into them.

### Exposing a gRPC API 

As in the previous post I'm using the branches of project [micro-media-service](https://github.com/johandry/micro-media-service) on Github, for this section it is  branch ``.

There are different proposals to organize a Go project but something that is always the same in all of them is the `api/proto/v1` directory to store the versions of the API definition or Protocol Buffer. 

