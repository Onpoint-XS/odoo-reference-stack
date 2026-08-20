from datetime import timedelta

from odoo import fields
from odoo.tests import TransactionCase, tagged


@tagged("post_install", "-at_install")
class TestDeployment(TransactionCase):
    """These run on every pull request.

    Not because a deployment log is difficult, but because a gate nobody can bypass is
    only worth having if there is something behind it. A repository whose CI passes
    because it tests nothing teaches the wrong habit.
    """

    def test_recent_flag_is_true_for_todays_deploy(self):
        record = self.env["reference.deployment"].create(
            {"name": "deploy-1", "module_version": "18.0.1.0.1"}
        )
        self.assertTrue(record.is_recent)

    def test_recent_flag_is_false_beyond_the_window(self):
        record = self.env["reference.deployment"].create(
            {
                "name": "deploy-old",
                "module_version": "18.0.1.0.0",
                "deployed_at": fields.Datetime.now() - timedelta(days=8),
            }
        )
        self.assertFalse(record.is_recent)

    def test_recompute_when_the_date_moves(self):
        # The failure this guards against: a stored compute that is correct on create
        # and silently stale afterwards, because the depends was wrong.
        record = self.env["reference.deployment"].create(
            {"name": "deploy-2", "module_version": "18.0.1.0.1"}
        )
        record.deployed_at = fields.Datetime.now() - timedelta(days=30)
        self.assertFalse(record.is_recent)

    def test_ordering_is_newest_first(self):
        model = self.env["reference.deployment"]
        model.search([]).unlink()
        older = model.create(
            {
                "name": "older",
                "module_version": "18.0.1.0.0",
                "deployed_at": fields.Datetime.now() - timedelta(days=2),
            }
        )
        newer = model.create({"name": "newer", "module_version": "18.0.1.0.1"})
        self.assertEqual(model.search([])[0], newer)
        self.assertEqual(model.search([])[1], older)
