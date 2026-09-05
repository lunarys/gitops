The Kargo flow that promotes the meta resources:

- Kargo Project (`kargo-platform`)
- Kargo Warehouse
- Kargo Stages that render `04_apps_generator` onto the stage branches


Separate from `03_apps_bootstrap` because these are Kargo resources, and the
Kargo CRDs do not exist at bootstrap time -- Kargo arrives with `05_apps`. A
tier is defined by what is available when it runs, so anything needing a CRD
that bootstrap cannot provide is not a bootstrap resource.

Applied by hand, once Kargo is up. There is deliberately no promotion flow for
this directory yet: it *is* the promotion flow, so promoting it with itself
means a bad render breaks the mechanism that would fix it. Kargo, unlike Argo
CD, cannot recover by re-reading git -- rendering is the part that breaks.
