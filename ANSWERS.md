# Assignment Answers
Q1. A platform is running around 40 Ingress objects on ingress-nginx, which has reached end-of-life. You need to migrate to the Kubernetes Gateway API with no downtime. Outline your approach, the order you would do things in, and what you expect to break along the way.

**Solution:** I have strong experience working with Kubernetes networking and Ingress-based routing, although I have not yet implemented an Ingress-to-Gateway API migration in a production environment. I am currently getting deeper into Gateway API and its components.

My understanding is that Gateway API provides a more structured and extensible approach to Kubernetes traffic routing, building on the concepts of Ingress while separating infrastructure-level configuration from application routing through resources such as `Gateway` and `HTTPRoute`.

For a migration, I would first map the existing ingress-nginx configuration and annotations to the equivalent Gateway API capabilities, validate the new routing path in parallel, and then migrate applications in controlled batches. I would keep the existing ingress-nginx path available during the transition so that traffic can be rolled back safely if any routing, TLS, or application-specific behavior differs.
