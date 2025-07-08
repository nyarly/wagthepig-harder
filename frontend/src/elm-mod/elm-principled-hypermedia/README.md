# Principled Hypermedia

Maybe too grand a name
or too grand an ideal.
The goal here is too support semantic API use,
as inspired by RDF, JSON-LD and Hydra.

Semantic or Hypermedia APIs
identify their resources with URLs
and link them together with hyperlinks,
much as simple HTML does for a user.
Operations that can be performed on a resource
are exposed as affordances.
In HTML, they would be encapsulated in a `form`,
and in Hydra, they're described with `operation` attributes.

This facilitates evolvable interfaces,
that client programs consume much like a human being does browsing a website.
They don't magically know dozens of paths and their parameters,
but instead they follow links from one resource to the next,
and find out how to manipulate resources via their operations.

Developers can use the API itself as its own documentation,
and the integration between client and server is more robust
in face of change because new links and parameters can be added over time.
New features can be exposed for future clients,
without breaking the assumptions of existing ones.

We provide this resiliancy
by following trails of links through the API,
and much of this library is focused on making that possible.

The `Hypermedia` module has common HTTP artifacts
(methods and status codes etc.)
along with tools for describing the path that we should follow
from the API root (the one URL we need to know)
to whatever resource we're concerned with.

`ResourceUpdate` holds functions to
facilitate manipulating specific REST resources.

Finally, `LinkFollowing`
allows arbitrary requests made at the "end" of
chains of requests, pulling the next link
from Hydra actions in each request.
Those interfaces are under consideration of deprecation.
