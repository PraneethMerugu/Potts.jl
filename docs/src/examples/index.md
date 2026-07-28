# [See what the engine can do](@id example-gallery)

These are complete, deterministic PottsToolkit programs—not screenshots of private scripts. Every
page exposes the model declarations, simulation setup, quantitative contract, and native
MakiePotts visualization.

```@raw html
<div class="potts-gallery">
  <a class="potts-card" href="relaxing-cell/">
    <img src="relaxing-cell-preview.svg" alt="Compressed and relaxed cell beside its volume error trace">
    <div class="potts-card-copy">
      <h3>A compressed cell relaxes</h3>
      <p>Connect geometry to a preferred-volume energy.</p>
      <span class="potts-contract">before/after + volume error</span>
    </div>
  </a>
  <a class="potts-card" href="differential-adhesion/">
    <img src="sorting-preview.svg" alt="Two cell populations and their heterotypic contact trace">
    <div class="potts-card-copy">
      <h3>Two populations sort</h3>
      <p>Watch costly heterotypic interfaces reorganize.</p>
      <span class="potts-contract">animation + contact statistic</span>
    </div>
  </a>
  <a class="potts-card" href="chemotaxis/">
    <img src="chemotaxis-preview.svg" alt="Migrating cell over a concentration gradient with displacement trace">
    <div class="potts-card-copy">
      <h3>A cell follows a gradient</h3>
      <p>See the prescribed field, path, and directed displacement.</p>
      <span class="potts-contract">animation + trajectory</span>
    </div>
  </a>
  <a class="potts-card" href="growth-and-division/">
    <img src="growth-and-division-preview.svg" alt="Cell identities and population counts during division and retirement">
    <div class="potts-card-copy">
      <h3>Grow, divide, retire</h3>
      <p>Combine property growth, division, and scheduled death.</p>
      <span class="potts-contract">animation + population history</span>
    </div>
  </a>
  <a class="potts-card" href="elongated-network/">
    <img src="elongated-network-preview.svg" alt="Elongated cell identities with shape metric">
    <div class="potts-card-copy">
      <h3>Acquire elongated shapes</h3>
      <p>Compose elongation, adhesion, and connectivity.</p>
      <span class="potts-contract">animation + morphology trace</span>
    </div>
  </a>
  <a class="potts-card" href="fluctuating-droplet/">
    <img src="fluctuating-droplet-preview.svg" alt="Fluctuating droplet with volume trace and distribution">
    <div class="potts-card-copy">
      <h3>Sample a fluctuating droplet</h3>
      <p>Put mechanical noise, history, and distribution together.</p>
      <span class="potts-contract">shape + trace + histogram</span>
    </div>
  </a>
  <a class="potts-card" href="boundaries-and-obstacles/">
    <img src="boundaries-preview.svg" alt="Cell adjacent to an immutable internal obstacle">
    <div class="potts-card-copy">
      <h3>Meet boundaries and obstacles</h3>
      <p>Distinguish closed faces from immutable internal sites.</p>
      <span class="potts-contract">semantic owners + exact assertion</span>
    </div>
  </a>
  <a class="potts-card" href="same-model-2d-3d/">
    <img src="same-model-2d-3d-preview.svg" alt="The same cell model rendered in 2D and as a 3D slice">
    <div class="potts-card-copy">
      <h3>Reuse one model in 2D and 3D</h3>
      <p>Separate biological declarations from realized geometry.</p>
      <span class="potts-contract">full frame + explicit slice</span>
    </div>
  </a>
  <a class="potts-card" href="stop-and-resume/">
    <img src="stop-and-resume-preview.svg" alt="Uninterrupted and restored states shown side by side">
    <div class="potts-card-copy">
      <h3>Stop and resume exactly</h3>
      <p>Prove logical-state equality after checkpoint restore.</p>
      <span class="potts-contract">side-by-side + exact equality</span>
    </div>
  </a>
  <a class="potts-card" href="reproducible-ensemble/">
    <img src="reproducible-ensemble-preview.svg" alt="Twelve volume trajectories and their final-value distribution">
    <div class="potts-card-copy">
      <h3>Expose ensemble variability</h3>
      <p>Derive semantic seeds and retain every trajectory.</p>
      <span class="potts-contract">replicates + distribution</span>
    </div>
  </a>
</div>
```

## Choose by scientific question

| If you want to understand… | Start with… |
|:--|:--|
| energetic relaxation | [A compressed cell relaxes](@ref relaxing-cell) |
| differential adhesion and sorting | [Two populations reduce unlike contacts](@ref differential-adhesion-example) |
| prescribed fields and directed motion | [A cell follows a prescribed gradient](@ref chemotaxis-example) |
| lifecycle rules and generation-aware identity | [Cells grow, divide, and retire](@ref growth-division-example) |
| elongation and connectivity constraints | [Cells acquire elongated, connected shapes](@ref elongated-network) |
| noisy mechanics and distributional analysis | [A droplet fluctuates](@ref fluctuating-droplet) |
| ownership boundaries and obstacles | [Closed boundaries and immutable obstacles](@ref boundaries-and-obstacles) |
| dimension-generic authoring | [One model, two and three dimensions](@ref same-model-2d-3d) |
| exact persistence | [Stop and resume](@ref stop-and-resume) |
| deterministic ensemble seeding | [A reproducible ensemble](@ref reproducible-ensemble) |

The examples make bounded claims about pinned trajectories. Published-model reproduction and
scientific qualification require the separate evidence contracts described under
[Scientific guarantees](@ref scientific-guarantees).
