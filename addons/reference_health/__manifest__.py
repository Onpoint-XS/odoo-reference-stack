{
    "name": "Reference Health",
    # This version is the thing the post-deploy assertion checks. Bump it in the same
    # commit as any change to this module, or CI fails the pull request and the deploy
    # assertion fails the release.
    "version": "18.0.1.0.1",
    "summary": "A deployment health endpoint, and something small enough to demonstrate upgrades against",
    "author": "ONPOINT XS",
    "license": "MIT",
    "category": "Technical",
    "depends": ["base"],
    "data": [
        "security/ir.model.access.csv",
        "views/deployment_views.xml",
    ],
    "installable": True,
    "application": False,
}
