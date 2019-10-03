---
title: "Introduction to Microservices in Go: Grpc"
date: 2019-05-26T08:39:00-07:00
tags: ["Golang", "Microservices", "gRPC", "Docker"]
draft: true
---

In the [previous post](http://blog.johandry.com/post/intro-microservice-in-go-1/) I explained how to create a REST/HTTP microservice using Go and Docker, this post is about creating a microservice using gRPC.

There are several advantages of gRPC over REST. There are many articles explaining in detail all of them so I'm going to name a few:

- gRPC is smaller and faster than REST. gRPC uses protobuf a binary that is smaller than a plain text JSON. The disadvantage is that REST is more easier to debug and visualize.
- gRPC has lower latency than REST because it uses HTTP/2, unless you use HTTP/2 with a REST API but usually is HTTP/1.1
- gRPC is bidirectional and async, REST instead works with request from the client to the server.
- gRPC support streams and REST only supports requests and responses opening a TCP connection for each one.
- gRPC is API oriented, you implements the API verbs you need in a free way. REST instead is CRUD oriented, the verbs to implement are only Create/Post, Retrieve/Get, Update/Put and Delete.
- gRPC protobuf generates the code in many languages, this cannot be done with pure REST, you need to use OpenAPI or Swagger.

Despite all these advantages over REST, it has one that beat gRPC: The current browsers support to gRPC is not mature yet, making it hard for users to interact with a gRPC API.  

gRPC is better used for internal communications, communication between microservices, but this does not mean that implementing gRPC is to resign to REST. It is possible to expose a REST API and the gRPC API thanks to the [gRPC gateway](https://github.com/grpc-ecosystem/grpc-gateway) and [gRPC-Web](https://github.com/grpc/grpc-web).

Having gRPC and REST APIs to expose, there are 4 options to consider: just REST (explained in the [previous blog post](http://blog.johandry.com/post/intro-microservice-in-go-1/)), <u>just gRPC</u>, <u>REST and gRPC</u> each one on its own endpoint (or port), and the last one is <u>gRPC and REST exposed in one single endpoint</u>. Lets get into the just gRPC mode.

### Exposing a gRPC API

As in the previous post I'm using the branches of project [micro-media-service](https://github.com/johandry/micro-media-service) on Github, for this section it is  branch `s04_grpc`.

gRPC uses a Protocol Buffer to define the API using an IDL, then we use the compiler `protoc` to generate the Go code to use it. Lets create this `.proto` file to define the media service API, but where?

There are different proposals for Go projects structure but something that is always similar in all of them to store the versions of the API definition, or protobuf, is the `api/[service]/proto/v1` directory.

The `.proto` file is like follows:

```protobuf
syntax = "proto3";

package media.v1;

message Movie {
  int64 id = 1;
  string title = 2;
  string description = 3;
  string genre = 4;
  repeated string artists = 5;
  string director = 6;
  float rating = 7;
  string release_date = 8;
}

service Media {
  rpc GetMovie(GetMovieRequest) returns (GetMovieResponse);
  rpc ListMovies(ListMoviesRequest) returns (ListMoviesResponse);
}

message GetMovieRequest {
  int64 id = 1;
}

message GetMovieResponse {
  Movie movie = 1;
}

message ListMoviesRequest {
}

message ListMoviesResponse {
  repeated Movie movies = 1;
}
```

The first line is the protobuf version, by the time this post is writen the latest one is version 3. It's followed by the Go package name definition. All the generated Go code will be on package `v1` in the directory `media/v1`.

Then we define the Movie message with the fields or data included in each type of movie message. Each field has a name and type, these types are all [scalar types](https://developers.google.com/protocol-buffers/docs/proto3#scalar) (integers, strings, boolean) but there are also composite types such as [enumerations](https://developers.google.com/protocol-buffers/docs/proto3#enum) and [maps](https://developers.google.com/protocol-buffers/docs/proto3#maps) and arrays or list using the keyword `repeated`. If you look at the message `GetMovieResponse` and `ListMoviesResponse` the `Movie` message is also a type. A message can also be empty, for example, the `ListMoviesRequest`.

The Protocol Buffer has to define at lease one service, this one defines `Media`. Inside the service we define the methods or Remote Procedure Calls (RPC). Each method has a single input and output, both in form of a message. If the method requires multimple input parameters or returns multiple values, those have to be encapsulated in a message.

The naming convention for protobuf is different to Go. The messages and services are capitalized, the field names are lowercase in snake case. The enums values (not in the example, yet) are uppercase.

#### Installing dependencies

The protobuf compiler or `protoc` is used to generate a Go code to use the API. Before that we need to download `protoc` and it's dependencies. Create a Makefile with the following rule:

```makefile
PROTOC_VERSION 	= 3.7.0

dependencies:
	go get -u google.golang.org/grpc
	go get -u github.com/golang/protobuf/{proto,protoc-gen-go}
	
	mkdir -p /tmp/protoc && \
	curl -sLk https://github.com/google/protobuf/releases/download/v$(PROTOC_VERSION)/protoc-$(PROTOC_VERSION)-$(MY_GOOS)-$(MY_GOARCH).zip | \
		tar -xzv -C /tmp/protoc
	mv /tmp/protoc/bin/protoc $(GOPATH)/bin
	rm -rf /usr/local/include/google
	mv /tmp/protoc/include/google /usr/local/include/
	go get -u github.com/grpc-ecosystem/grpc-gateway/{protoc-gen-grpc-gateway,protoc-gen-swagger}


	$(RM) -rf /tmp/protoc
```

The `dependencies` rule download all the protobuf libraries or Go packages used to compile the protobuf code. It also install 

Execute `make dependencies` now and everytime the repository is cloned.

Some Go developers move the google libraries from the downloaded `include/google` directory into the repository. If you do it, it's recommended to store it in the directory `

