---
title: "Introduction to Microservices in Go"
date: 2017-11-10T14:20:08-08:00
draft: true
---

# Introduction to Microservices in Go

This is just a very simple example about how to build a microservice in Go, it's not perfect as it is made for Go and Microservices learning.

The purpose of this microservice is a catalog of the movies I own or want to watch. The code of this simple microservice is at https://github.com/johandry/movie and every section is a branch. Clone the repository and change branch for every section.

    git clone https://github.com/johandry/movie

## A simple RESTful API

Let's start with a simple RESTfull API by making a simple web server. To get the code for this section by checking out branch `s01-restful-api`:

    git checkout s01-restful-api

Every output to the terminal in this microservice uses the `log` package instead of the `fmt`'s prints. So let's start this example with

{{<highlight golang>}}
package main

import "log"

const port = 8086

func main() {
	log.Printf("Starting movies microservice on port %d", port)
}
{{</highlight>}}

Now lets create a simple web server to respond with the microservice version when we open the URL `/api/v1/version`

{{<highlight golang>}}
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

We call the `HandleFunc` method to create a `Handler` type on the default handler (`DefaultServerMux` from `net/http` package), mapping the path `"/api/v1/version"` to the function `handleVersion`.

Then we start the HTTP server with `ListenAndServe` that takes two parametersm the TCP network address to bind the server and the used to route requests. In this example the bind address is `":8086"` (port `8086` on every available IP) and as the handler is `nil` it will use the default one (`DefaultServerMux`).

The return value of `ListenAndServe` is an error and if there is any (the error is not `nil`) it will be printed by `log.Fatal` method and exit with code 1 (it calls `os.Exit(1)`). The `ListenAndServe` method blocks the program until there is an error or someone or something stop it.

To view your masterpiece in action, start your program with `go run main.go` and open a in a browser or with curl the URL: http://localhost8086/api/v1/version.

What will happen if you start the program twice?

## Let's speak in JSON

The version output in our example was plain text, now let's see how can we accept and return JSON. The package `encoding/json` is going to help us to encode and decode JSON to/from Go type structures using the `Marshal`,  `Unmarshal`, `Encoder` and `Decoder` functions.

We need to return the version so we'll encapsulate it in a structure, modify the global variable and use the `init` function to initialize it.

{{<highlight golang>}}
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

The version handler function was also modified to marshal the version variable. If there is an error marshaling the structure the program will panic, if not we convert the `verJSON` to string as it is a `[]byte` type and return it to the user.

If we run this the response will be `{}` and this is because the `version` property inside the struct `Version` is not exported. Changing it to `Version string` we get this output `{"Version":"0.1.0"}` which is kind of the expected result but with the JSON field in lowercase. To make `Marshal` to not use the default name of the JSON field as the property name we have to use struct field attributes. So the `version` struct should like this:

{{<highlight golang>}}
type Version struct {
	Version string `json:"version"`
}
{{</highlight>}}

In this example it's ok to return the JSON in one line but if we want to make it pretty we use the function `MarshalIndent` like this:

{{<highlight golang>}}
verJSON, err := json.MarshalIndent(version, "", "  ")
{{</highlight>}}

But we are also going to return a movie object based on its ID or all the stored movies. So, let's have a movie structure and mock it with some values:

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
