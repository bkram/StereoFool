# Vulture whitelist for framework-registered callbacks.
# Keep in sync with Flask/SocketIO handlers.
from stereofool import app as app_module

app_module.app.secret_key
app_module.index
app_module.rds_ui
app_module.mpx_ui
app_module.login
app_module.logout
app_module.enforce_allowlist
app_module.save_settings
app_module.handle_update
app_module.handle_control
