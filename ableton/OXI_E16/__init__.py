"""Live loads a Remote Script by calling create_instance() on the package."""

from .oxi_e16 import OxiE16


def create_instance(c_instance):
    return OxiE16(c_instance)
