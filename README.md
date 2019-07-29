# My Blog

This is the source code and content of my [blog](http://blog.johandry.com). It's built with [Hugo](https://gohugo.io/), a great framework to build static web sites.

Most of the actions are automated in a Makefile, so most of the required actions are done with `make`, but everything else is documented here.

The main requirement for this blog is [Hugo](https://gohugo.io/), install it executing: `brew install hugo`.

After cloning the repository, download (or clone) the blog theme:

```bash
mkdir themes
cd themes
git clone https://github.com/yoshiharuyamashita/blackburn.git
```

## New Post

To create a new post execute:

```bash
make post T='Title of the Post'
```

Then edit the file `content/post/<title-of-the-post>.md` to add the post content. Use the command  `hugo server -D` and go to [localhost:1313](http://localhost:1313) to view the live changes to the new post.

Make sure to:

1. Edit the metadata to add the tags like this: `tags: ["Hugo", "Blogging"]`
2. Remove the `draft` variable in the metadata section when you are ready to publish it

Once it's done, run `hugo server` to do a final validation before deploy to GitHub. Stop `hugo server` and commit the changes to the post branch:

```bash
git status
git add --all
git commit -m "Post <title>"
git push
```

Create a Pull Request to merge the new post branch into master branch. Finally, re-build the blog site executing:

```bash
make build push
```

The content of the blog, is in the directory `public/` (re-created by `build`) which is where the branch `gh-pages` is (synced by `push`). You can also execute `make all`.

Verify the new post on-line.

## Initial process

Everything I did to create this blog is documented in my second post: [A New Blog on GitHub](http://blog.johandry.com/post/a-new-blog-on-github/).
