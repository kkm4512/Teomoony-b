import sys; sys.path.insert(0, "/app/Teomoony/data/pylib312")
from pyiceberg.table import Table
from pyiceberg.table.update.snapshot import ManageSnapshots
import inspect
print("ManageSnapshots:", [m for m in dir(ManageSnapshots) if not m.startswith("_")])
print("Table:", [m for m in dir(Table) if not m.startswith("_")])
try:
    from pyiceberg.table.maintenance import MaintenanceTable
    print("Maintenance:", [m for m in dir(MaintenanceTable) if not m.startswith("_")])
except Exception as e: print("no maintenance", e)
print(inspect.signature(Table.scan))
print(inspect.signature(Table.overwrite)); print(inspect.signature(Table.append))
