from pathlib import Path

from cc3d.core.PySteppables import SteppableBasePy


STATE = {"code": 0, "field_before": 0.0, "rows": []}


class BeforeMCS(SteppableBasePy):
    def step(self, mcs):
        field = self.field.sentinel
        STATE["code"] = 1
        STATE["field_before"] = float(field[0, 0, 0])
        field[0, 0, 0] = 3.0


class FirstNormal(SteppableBasePy):
    def step(self, mcs):
        STATE["code"] = 10 * STATE["code"] + 2


class SecondNormal(SteppableBasePy):
    def step(self, mcs):
        STATE["code"] = 10 * STATE["code"] + 3


class FrequencyTen(SteppableBasePy):
    def step(self, mcs):
        STATE["code"] = 10 * STATE["code"] + 4


class Recorder(SteppableBasePy):
    def step(self, mcs):
        STATE["rows"].append(
            (
                mcs,
                STATE["code"],
                STATE["field_before"],
                float(self.field.sentinel[0, 0, 0]),
            )
        )

    def finish(self):
        output_path = Path(self.output_dir).joinpath("wang_order_trace.csv")
        with output_path.open("w") as output:
            output.write("mcs,python_code,field_before,field_after\n")
            for row in STATE["rows"]:
                output.write("{},{},{:.17g},{:.17g}\n".format(*row))
