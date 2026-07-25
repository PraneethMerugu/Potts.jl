from cc3d import CompuCellSetup

from wang_order_oracle_Steppables import (
    BeforeMCS,
    FirstNormal,
    FrequencyTen,
    Recorder,
    SecondNormal,
)

before = BeforeMCS(frequency=1)
before.runBeforeMCS = 1
CompuCellSetup.register_steppable(steppable=before)
CompuCellSetup.register_steppable(steppable=FirstNormal(frequency=1))
CompuCellSetup.register_steppable(steppable=SecondNormal(frequency=1))
CompuCellSetup.register_steppable(steppable=FrequencyTen(frequency=10))
CompuCellSetup.register_steppable(steppable=Recorder(frequency=1))

CompuCellSetup.run()
