# Johandry's Blog ([blog.johandry.com](http://blog.johandry.com))

This is the source code and content of my blog. It's built with [Hugo](https://gohugo.io/), a great framework to build static web sites.

Everything here is automated in a Makefile, so most of the required actions are done with `make`, but everything else is documented here.

The main requirement for this blog is [Hugo](https://gohugo.io/), install it executing: `brew install hugo`.

## New Post

To create a new post:
1. Execute `hugo new post/<title-file>.md`
2. Edit the file `content/post/a-new-blog-on-github.md` to add the post content.
3. Edit the metadata to add the tags like this: `tags: ["Hugo", "Blogging"]`
4. Remove the `draft` variable in the metadata section when you are happy with the content

During the edition process (step #2) you may use `hugo server -D` to view the changes to the new post. Once it's done, run `hugo server` to do a final validation before deploy to GitHub.

Once you are happy with the changes, stop `hugo server` and execute:

    git status
    git add --all
    git commit -m "Post <title>"

Regenerate the `public/` directory with the new post and push it to Github with:

    make build push

Now verify the new post on-line.

## Initial process

Everything I did to create this blog is documented in my second post: [A New Blog on GitHub](http://blog.johandry.com/post/a-new-blog-on-github/).
