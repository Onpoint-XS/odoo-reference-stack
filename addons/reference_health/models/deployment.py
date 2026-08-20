import logging
from datetime import timedelta

from odoo import api, fields, models
from odoo.http import Controller, request, route

_logger = logging.getLogger(__name__)


class DeploymentRecord(models.Model):
    """One row per deploy.

    Small on purpose. Its real job is to be a module that can be changed, versioned
    and rolled back so the pipeline can be demonstrated end to end. But the record it
    keeps is genuinely useful: when something starts misbehaving, the first question
    is always what changed and when, and the answer usually is not in anyone's memory.
    """

    _name = "reference.deployment"
    _description = "Deployment record"
    _order = "deployed_at desc"

    name = fields.Char(required=True, index=True)
    commit_sha = fields.Char(string="Commit", size=40, index=True)
    module_version = fields.Char(required=True)
    deployed_at = fields.Datetime(default=fields.Datetime.now, index=True)
    rolled_back = fields.Boolean(default=False, index=True)
    notes = fields.Text()

    # Stored and indexed deliberately. An unstored compute read in a list view is one
    # of the most common reasons an Odoo list gets slow as the table grows, because it
    # is evaluated in Python for every row on every render.
    is_recent = fields.Boolean(
        compute="_compute_is_recent",
        store=True,
        index=True,
        help="Deployed within the last seven days.",
    )

    @api.depends("deployed_at")
    def _compute_is_recent(self):
        cutoff = fields.Datetime.now() - timedelta(days=7)
        for record in self:
            record.is_recent = bool(record.deployed_at and record.deployed_at >= cutoff)


class HealthController(Controller):
    """Health endpoints.

    A container that is running is not the same as an Odoo that is serving. The
    compose healthcheck hits /web/health, which Odoo provides. This adds a check that
    also proves the ORM and the database connection are alive, which is the difference
    between "the process is up" and "the application works".
    """

    @route("/reference/health", type="http", auth="none", csrf=False, save_session=False)
    def health(self):
        try:
            request.env(su=True)["ir.module.module"].search_count([("state", "=", "installed")])
        except Exception:
            _logger.exception("health check failed")
            return request.make_response("unhealthy", status=503)
        return request.make_response("ok", status=200)
