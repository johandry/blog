---
title: "Introduction to Microservices in Go, part 1"
date: 2017-11-10T14:20:08-08:00
---

This is a very simple example about how to build a microservice in Go. It's meant for a quick Go and Microservices tutorial series covering from the a RESTful API to gRPC on Kubernetes.

The purpose of this microservice is a catalog of movies. The code is at https://github.com/johandry/micro-media-service and every section is a branch, clone the repo and change branch for every section.

    git clone https://github.com/johandry/micro-media-service

## A simple RESTful API

Let's start with a simple RESTfull API by making a simple web server. Get this section code by checking out the branch `s01-restful-api`:

    git checkout s01-restful-api

All the microservice terminal output is done using the `log` package instead of the `fmt`'s prints. So let's start this example with

{{<highlight golang>}}
package main

import "log"

const port = 8086

func main() {
	log.Printf("Starting movies microservice on port %d", port)
}
{{</highlight>}}

Now lets create a simple web server to print the microservice version when we hit the URL `/api/v1/version`

{{<highlight golang "linenos=inline">}}
package main

import (
	"fmt"
	"log"
	"net/http"
)

const port = 8086

var version = "0.1.0"

func main() {
	http.HandleFunc("/api/v1/version", handleVersion)

	log.Printf("Starting movies microservice on port %d", port)
	log.Fatal(http.ListenAndServe(fmt.Sprintf(":%d", port), nil))
}

func handleVersion(rw http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(rw, "Version: %s", version)
}
{{</highlight>}}*

At line #4 we call the `HandleFunc()` method to create a `Handler` type on the default handler `DefaultServerMux` from the `net/http` package, mapping the path `"/api/v1/version"` to the function `handleVersion()` defined at line #20.

Then at line #17 we start the HTTP server with `ListenAndServe()` that takes two parameters, the TCP network address to bind the server and the handler to route the requests. In this example the bind address is `":8086"` (port `8086` on every available IP) and, as the handler is `nil`, it will use the default one (`DefaultServerMux`).

The return value of `ListenAndServe()` is an error and if there is any (the error is not `nil`) it will be printed by `log.Fatal` method and exit with code 1 by calling `os.Exit(1)`. The `ListenAndServe()` method blocks the program until there is an error or someone stop it.

To view your masterpiece in action, start your program with `go run main.go` and open the URL http://localhost8086/api/v1/version in a browser or with curl.

What will happen if you start the program twice?

## Let's speak in JSON

The output in this first example is the version number in plain text, now let's see how can we print it in JSON format. The package `encoding/json` is going to help us to encode and decode JSON to/from Go type structures using the `Marshal`,  `Unmarshal`, `Encoder` and `Decoder` functions.

To return the version we are going to encapsulate it in a structure (line #1 to #3), modify the global variable `version` to be of the defined `Version` type (line #5) and use the `init()` function to initialize it (line #8).

{{<highlight golang "linenos=inline">}}
type Version struct {
	version string
}

var version Version

func init() {
	version = Version{"0.1.0"}
}

func handleVersion(rw http.ResponseWriter, r *http.Request) {
	verJSON, err := json.Marshal(version)
	if err != nil {
		panic("Error marshaling version")
	}
	fmt.Fprintf(rw, string(verJSON))
}
{{</highlight>}}*

The version handler function was also modified to marshal (to encode) the `version` variable to JSON. If there is an error marshaling the structure the program will panic, if not we convert `verJSON` to string because [`Marshal()`](https://golang.org/pkg/encoding/json/#Marshal) returns the JSON as a `[]byte` type but [`Fprintf()`](https://golang.org/pkg/fmt/#Fprintf) is waiting for a string.

If we run this the response will be `{}` and this is because the `version` property inside the struct `Version` is not exported. Changing the property to `Version string` will return this output `{"Version":"0.1.0"}` which is kind of the expected result but the JSON field should be in lowercase. The `Marshal()` method by default uses the name of the struct property to name the JSON field, to change this default behavior we have to use struct field attributes. So the final `Version` struct should like this:

{{<highlight golang>}}
type Version struct {
	Version string `json:"version"`
}
{{</highlight>}}

In this example it's ok to return the JSON in one line but if we want to print it in pretty format we use the function `MarshalIndent()` like this:

{{<highlight golang>}}
verJSON, err := json.MarshalIndent(version, "", "  ")
{{</highlight>}}

The main function of this microservice is to return movie objects. So, let's have a movie structure and initialize it with some testing values:

{{<highlight golang>}}
type Movie struct {
	ID          int      `json:"id, string"`
	Title       string   `json:"title"`
	Description string   `json:"desc"`
	Genre       string   `json:"genre"`
	Artists     []string `json:"artists"`
	Director    string   `json:"director"`
	Rating      float64  `json:"-"`
	ReleaseDate string   `json:",omitempty"`
}

var movies  []Movie

func init() {
	version = Version{"0.1.0"}
	movies = []Movie{
		...
	}
}

func main() {
	http.HandleFunc("/api/v1/movies", handleMovies)
	...
}
{{</highlight>}}

If you want to see all the movies, please, get the code. It's a long list even with 5 items.

We are also mapping the path `"/api/v1/movies"` to the handler function `handlerAllMovies` to respond all the movies in JSON but in this case we'll use the `Encoder` object from `encoding/json` that's more efficient than marshaling and return a string, so the handler function to respond all the movies looks like this:

{{<highlight golang>}}
func handleMovies(rw http.ResponseWriter, r *http.Request) {
	encoder := json.NewEncoder(rw)
	encoder.Encode(&movies)
}
{{</highlight>}}*

When we open the URL http://localhost:8086/api/v1/movies we do not get the JSON pretty but if we can get it pretty if we use `curl` and [`jq`](https://stedolan.github.io/jq/download/)

    curl -s http://localhost:8086/api/v1/movies | jq

## Returning just one movie

Before continue working with a single file (`main.go`) with all the code, let's first split all the code in different files. Change to the branch `s02-read-json` where you can see the files `main.go`, `version.go` and `movies.go`. Now use `go run *.go` to run the microservice.

Let's create a path that receives something after `"/movies/"` like an ID and map it to a handler function to return the movie with that ID.

In `main.go`:
{{<highlight golang>}}
func main() {
  http.HandleFunc("/api/v1/movies/", handleMovieFromID)
  ...
}
{{</highlight>}}

In `movies.go` we create a RegEx to parse a number after `"/movies/"`, for this we create a compiled RegEx structure that we'll use later to find all the strings that match the pattern. If this match is a number and it is a valid ID of a movie, then respond with the movie in JSON format.

{{<highlight golang>}}
var reMovieID *regexp.Regexp

func handleMovieFromID(w http.ResponseWriter, r *http.Request) {
  values := reMovieID.FindStringSubmatch(r.URL.Path)
  if len(values) < 1 {
		http.Error(w, fmt.Sprintf("Bad request. Not valid ID (%v) in request '%s'", path.Base(r.URL.Path), r.URL.Path), http.StatusBadRequest)
		return
	}
	id, err := strconv.Atoi(values[1])
	if err != nil {
		http.Error(w, fmt.Sprintf("Bad request. Non numeric ID (%v) in request '%s'", values[1], r.URL.Path), http.StatusBadRequest)
		return
	}
	if id <= 0 || id > len(movies) {
		http.Error(w, fmt.Sprintf("Bad request. Out of range ID (%d) in request '%s'", id, r.URL.Path), http.StatusBadRequest)
		return
	}
	encoder := json.NewEncoder(w)
	encoder.Encode(&movies[id-1])
}

func init() {
	reMovieID, _ = regexp.Compile("/movies/([0-9]+)")
	...
}
{{</highlight>}}*

Check it by opening in a browser or using `curl` the following URLs:

* http://localhost:8086/api/v1/movies/foo/2
* http://localhost:8086/api/v1/movies/6
* http://localhost:8086/api/v1/movies/3
* http://localhost:8086/api/v1/movies/0

All these kind of complex routes can be managed very easy with the [`gorilla/mux`](http://www.gorillatoolkit.org/pkg/mux) package. However, let's look at other way to send information to the API.

## Let's read JSON

Besides receive input data from the URL the API can receive input data in the body of the request using JSON format. To implement this let's create a struct to store the request (this may not be necessary but will make the code more human readable).

{{<highlight golang>}}
type movieRequest struct {
	Title string `json:"title"`
}
{{</highlight>}}

Now modify the function `handleMovies` to read the request body, if there is no body then respond with all the movies, if there is a body and it contain a JSON with the title field, it will search for the movie and return the it in JSON format if it is found.

{{<highlight golang>}}
func handleMovies(w http.ResponseWriter, r *http.Request) {
  var req movieRequest
	encoder := json.NewEncoder(w)
	decoder := json.NewDecoder(r.Body)

	err := decoder.Decode(&req)
	if err != nil {
		encoder.Encode(&movies)
		return
	}

	if movieResponse, ok := searchMovie(req.Title); ok {
		encoder.Encode(&movieResponse)
	} else {
		http.Error(w, fmt.Sprintf("Not found movie with title '%s'", req.Title), http.StatusBadRequest)
	}
}
{{</highlight>}}*

To check this use `curl` and pass the JSON request with the parameter `-d`:

```
curl -s http://localhost:8086/api/v1/movies -d '{"title":"Kagemusha"}'
curl -s http://localhost:8086/api/v1/movies -d '{"title":"Frankestein"}'
curl -s http://localhost:8086/api/v1/movies | jq
```

## Build and Ship it

It's not done yet, there are many things missing but to see this beauty running as a microservice we have to containerize it, bake it into a container. This section works with the branch `s03-container`.

    git checkout s03-container

We'll use Docker to create the container and multi-stage builds to create a tiny Docker image. Let's starts with a single-stage `Dockerfile` file to create a Docker image based on Alpine to build our new microservice.


{{<highlight dockerfile>}}
FROM golang:alpine

WORKDIR /app
ADD . /app

RUN cd /app && go build -o movie

EXPOSE 8086

ENTRYPOINT [ "./movie" ]
{{</highlight>}}

Now build, run, test and destroy the container

    docker build -t johandry/movie .
    docker run --rm -p 80:8086 --name movie johandry/movie &
    curl -s http://localhost/api/v1/movies/1 | jq
    docker stop movie

As you can see we access the API on port `80` because the container expose the API on port `8086` and we map it to port `80` with the option `-p 80:8086`.

The image size is **276MB** (we can see this with `docker images`) it's considerable smaller compared with the **718MB** of an image based on Debian Jessie (try it replacing `FROM golang:alpine` by `FROM golang:1.8-jessie`) but we can make it smaller because in containers size matters. Let's start with changing to a multi-stage build by replacing the `Dockerfile`

{{<highlight dockerfile>}}
# Build stage
FROM golang:alpine AS build

ARG PKG_NAME=github.com/johandry/micro-media-service

ADD . /go/src/${PKG_NAME}

RUN cd /go/src/${PKG_BASE}/${PKG_NAME} && \
    go build -o /movie

# Run stage and microservice image
FROM alpine

COPY --from=build /movie .

EXPOSE 8086

ENTRYPOINT [ "./movie" ]
{{</highlight>}}

If you build, run, test and destroy the container with the same instructions you get the same results but the big difference is the size of the image, it's now **10.6MB**. In this example we are using Alpine but you can get the same size replacing it with Debian Stretch (`FROM golang:stretch`)

Can we make it smaller?

Yes, we can build the image from Scratch instead of Apline but not all the applications can support it. Some Go applications require libraries that are not provided using Scratch but in this yet simple microservice we can do it. Replace the Go build line to `CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o /movie` and the `FROM` instruction in the second stage to `FROM scratch`.

{{<highlight dockerfile>}}
# Build stage
FROM golang:alpine AS build

ARG PKG_NAME=github.com/johandry/micro-media-service

ADD . /go/src/${PKG_NAME}

RUN cd /go/src/${PKG_BASE}/${PKG_NAME} && \
    CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o /movie

# Run stage and microservice image
FROM scratch

COPY --from=build /movie .

EXPOSE 8086

ENTRYPOINT [ "./movie" ]
{{</highlight>}}

The final size of the image: **6.62MB**!!

In a next post about gRPC and Kubernetes, we'll use this and other containers interacting.

## One more thing ...

Before go to the next post I'd like to add to this microservice the option to configure it. This is a simple code so there isn't much to configure but let's give it the option to run in verbose mode.

Besides the build-in `log` package, there are many others like [`logrus`](https://github.com/sirupsen/logrus) and [`glog`](https://github.com/golang/glog). I have a preference for `logrus` so instead of implement my own,  I'll use it in this example. If you don't have it, get this package with

    go get github.com/sirupsen/logrus

Modify the `main.go` to define and get the flag `--verbose`, and get the value of the environment variable **`MOVIE_VERBOSE`** in lowercase. If the environment variable is `"true"` or if the flag `--debug` is used, then set the debug log level. This means that when I use the logrus function `Debug()`, `Debugf()` or `Debugln()` it will print the message, otherwise it won't because the default log level is Info.

As logrus is API-compatible with the standard `log` package we can create the alias `log` to `logrus` by replacing the import of log to:

{{<highlight golang>}}
    log "github.com/sirupsen/logrus"
{{</highlight>}}

And add to `main.go` the following lines:

{{<highlight golang>}}
var verboseFlag bool

func init() {
	flag.BoolVar(&verboseFlag, "verbose", false, "Enable verbose mode")
	flag.Parse()
	if verboseEnv := strings.ToLower(os.Getenv("MOVIE_VERBOSE")); verboseEnv == "true" || verboseFlag {
		log.SetLevel(log.DebugLevel)
	}
	formatter := &log.TextFormatter{
		FullTimestamp: true,
	}
	log.SetFormatter(formatter)
}
{{</highlight>}}

Modify the `log.Printf()` line in `verbose.go` to `log.Debugf()` and run it with:

```
go run *.go --verbose &
curl http://localhost:8086/api/v1/version
```

You can modify the `formatter` to change the output format or create your own. ([here is an example](https://github.com/johandry/log/blob/master/text_formatter.go))

I also recommend to use the [**Viper**](https://github.com/spf13/viper) and [**Cobra**](https://github.com/spf13/cobra) packages to implement the configuration of your Go programs. Viper manage the settings from environment variables and configuration files (yaml, json, toml and others). Cobra manage the parameters and flags. Both have the same author and play very well together.

Stay in tune for the next post to cover gRPC and Kubernetes. I'll update this line as soon as I have it.
