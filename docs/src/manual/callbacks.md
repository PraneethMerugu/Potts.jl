# [Callbacks](@id manual-callbacks)

Callbacks run your own code during a solve, as in SciML. A `DiscreteCallback(condition,
affect!)` checks `condition(u, t, integrator)` after every MCS and, when it is true, calls
`affect!(integrator)`. Inside `affect!` use the integrator's setters:

- `integrator.ps[:λ] = v` changes a parameter from the next MCS;
- `integrator[:x] = v` writes a declared variable;
- `terminate!(integrator)` stops the run;
- after writing `integrator.u` directly (for example cell kinds), call
  `derivative_discontinuity!(integrator, true)` so that frozen sites are recomputed.

`CallbackSet(cb₁, cb₂)` combines callbacks; pass them with `solve(…; callback = …)`.

A callback that fires saves the state, as in SciML. With the default `save_positions =
(true, true)`, each firing adds two saved states at that MCS: one before `affect!` and one
after it. A `saveat` time at which a callback fires is saved once, before the affect. A
callback that only records or changes a parameter usually needs no saves of its own: pass
`save_positions = (false, false)`, so the solution holds only the `saveat` states. This
matters on large lattices, where each saved state is a copy of the lattice.

```@example callbacks
using Potts
using Potts.Layouts

@potts_model Quench begin
    @kinds medium cell
    @parameters T = 15.0
    @variables tagged(cell) = 0.0
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != neighbor_kind)
    end
    @sweep Metropolis(; temperature = T)
end

@named quench = Quench()
op = layout(Tiling((5, 5); region = (6:25, 6:25), spacing = 1, kinds = [:cell]), quench)
prob = PottsProblem(quench, op, (0, 200); seed = 1)

cool = DiscreteCallback((u, t, integ) -> t == 50, integ -> (integ.ps[:T] = 1.0))
tag = DiscreteCallback((u, t, integ) -> t == 60, integ -> (integ[:tagged] = 1.0))
stop = DiscreteCallback((u, t, integ) -> t == 120, terminate!)
sol = solve(prob, SequentialCPM(); callback = CallbackSet(cool, tag, stop), saveat = 40)
sol.t, sol.retcode, sol[:tagged][end][1]
```

The run stopped at MCS 120 with return code `Terminated`. The `condition` sees `t` (the
MCS just completed) and `u`, a view of the state; keep conditions cheap, since they run
after every MCS.

## Write frames to disk

`FrameWritingCallback` writes states to disk while the run continues. Use it for long or
large runs whose saved states do not fit in memory:

```julia
using JLD2   # loads the file writer

cb = FrameWritingCallback(FrameFile("run_frames"); saveat = 10)
solve(prob, SequentialCPM(); callback = cb, save_everystep = false)

frames = PottsFrames("run_frames"; prob)
frames.t            # the MCS of each frame: [0, 10, 20, …]
frames(50)          # the state at MCS 50
frames[end]         # the last frame
close(frames)
```

The callback does not change what the solution saves. Pass `save_everystep = false` or
`saveat` to the solve, so that the states are on disk only. `PottsFrames` reads one frame at
a time, when you index it. MakiePotts records and explores it one frame at a time:
`record_potts("run.mp4", frames)`.

Put `FrameWritingCallback` first in a `CallbackSet`, so that it writes the state before
other callbacks change it. A `FrameFile` holds one run. A second run with the same callback
is refused, and so is a second `FrameFile` at a path that is being written. In an
ensemble, make the callback in `prob_func`, with a path for each trajectory.

`FrameFile` writes a directory of segment files and closes a segment every `checkpoint`
frames (default 10). If the process is killed (out of memory, a GPU reset, `SIGKILL`), the
closed segments stay readable. The run then loses at most `checkpoint` + 2 frames: the
segment that was open or closing, and the frames in the buffers. `PottsFrames` skips an unreadable last segment with a
warning. An operating system crash can also lose data that was not yet on the disk.

!!! details "How the writer works"
    At each frame time the callback starts a copy of the state into one of two reused host
    buffers. On a GPU these buffers are pinned and the copy is asynchronous. A writer task
    writes the other buffer to disk, so the next MCS does not wait for the disk. Start
    Julia with 2 or more threads (`julia -t 2`), so that the writer task runs beside the
    solve. On a 2016² lattice on ROCm, frames every 10 MCS cost about 7 % of the run time
    over 20000 MCS (31.5 GiB written), and memory stays flat.

    A write error stops the run at the next frame or at the end of the solve, as a
    `FrameWriteError`. After a normal finish, an error or an interrupt, the last segment
    is closed, and the directory holds every frame written before the stop. If you drive
    the integrator by hand, the frames are complete after `solve!(integ)`; to stop early,
    call `terminate!(integ)` and then `solve!(integ)`. `save_idxs = [:ownership]` writes
    only the ownership array.

    To write another format, subtype `AbstractFrameWriter` and add methods for
    `open_frames!`, `write_frame!` and `close`. To read it with `PottsFrames`, add
    `frame_times` and `read_frame`.
