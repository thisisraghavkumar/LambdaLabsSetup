# Portable Lambda Labs RL/ML Setup

A workflow for resuming RL/ML work on Lambda Labs GPU instances in minutes instead of
redoing setup every session, while paying for persistent storage of only what's
actually expensive to lose or regenerate.

## Introduction and quickstart

Picture the scenario this repo exists for: you've got an RL or ML project you chip
away at for a couple of hours on a Saturday, on a GPU that costs real money by the
hour. You spin up a Lambda Labs instance, and by the time you've reinstalled MuJoCo,
re-downloaded your model weights, and re-authenticated with GitHub, half your session
is already gone. Then you delete the instance to stop the bill, and next weekend you
do the whole thing over again. This repo exists to make every session after the first
one start in seconds instead of minutes, by keeping the expensive stuff — your custom
Python packages, downloaded models, training checkpoints, and GitHub credentials — on
a small, cheap slice of persistent storage that survives even when the GPU instance
itself doesn't.

Here's the fast path, assuming you've already got a Lambda Cloud account:

1. **Clone this repo** somewhere you'll remember it, and generate a GitHub deploy key
   it can use to check out your actual project code without you re-authenticating
   every week (the exact command is in "One-time setup" below).
2. **Create a persistent filesystem** in the Lambda console — a one-time, few-click
   job — in a region that has the GPU types you'll actually use.
3. **Launch an instance**, and remember to attach that filesystem at launch time —
   Lambda won't let you bolt it on afterwards, so it's worth double-checking before
   you hit go.
4. **SSH in, clone this repo onto the instance, and run one command**:
   `source bootstrap.sh <your-project>`. The first time, it builds a lean Python
   environment for your project; every time after that, it just switches it back on —
   a few seconds, not a few minutes.
5. **Do your work.** Checkpoints, datasets, and downloaded models all land on the
   persistent filesystem automatically, so nothing you generate disappears along with
   the instance.
6. **Terminate the instance** from the console when you're done for the day.
   Everything that matters is already stored safely — you're only paying a few cents
   a month to keep it there until you come back.

That's really the whole idea. The rest of this README fills in the details — why it's
built this way, what to expect the first time versus every time after, and how to
wire up a new project — but with the six steps above, you're most of the way there
already.

## Why it's built this way

Lambda Stack images already ship PyTorch, CUDA, numpy, and friends. Lambda's
persistent filesystems bill **$0.20/GB/month continuously**, even while no instance is
running, with no ingress/egress fees. So this setup persists only the *delta*:

- Extra Python packages not already in Lambda Stack (mujoco, safety-gymnasium, etc.),
  kept small via a venv built with `--system-site-packages`, which inherits the base
  image's heavy packages instead of duplicating them.
- The HuggingFace cache (downloaded model weights/datasets) — expensive to re-download.
- Training checkpoints and generated datasets — expensive to regenerate.

Project **code** stays in git and gets cloned/pulled fresh onto the instance's
ephemeral disk each session — that part is free and fast, so there's no reason to pay
to persist it.

## Facts about Lambda Cloud persistent storage that this setup assumes

- A filesystem must be attached to an instance **at launch time only** — you can't
  attach one after the instance already exists.
- Filesystems are **region-locked**: they only attach to instances in the same region,
  and can't be moved or transferred between regions.
- Mount path is `/lambda/nfs/<filesystem-name>`.
- Storage keeps billing at $0.20/GB/month between sessions, independent of whether any
  instance is running — terminating the instance stops compute billing but not storage
  billing.

## One-time setup

1. **Create the filesystem** in the Lambda console: Storage → Create filesystem. Name
   it (e.g. `ml-persist`) — alphanumeric + dashes only, no underscores/spaces.
   **Pick the region carefully**: since filesystems can't move between regions, check
   the [instance types page](https://cloud.lambda.ai/instances) to confirm your
   region has capacity for *both* the cheap dev/test instance type you'll use weekly
   and the larger production instance type you'll eventually scale to. If no single
   region has both, you'd need two separate filesystems (and duplicated HF cache /
   checkpoints) — worth checking now rather than discovering it later.
2. Clone this repo to your Mac and push it to a GitHub/GitLab remote you control —
   instances will clone it fresh each session.
3. If your filesystem name isn't `ml-persist`, either rename it to match, or export
   `LAMBDA_FS_NAME=<your-name>` before sourcing `bootstrap.sh` each session.
4. **Generate a dedicated GitHub deploy key** (don't reuse `id_ed25519` — that one's
   registered with Lambda for logging into instances, keep it separate from GitHub
   auth):
   ```bash
   ssh-keygen -t ed25519 -f github_deploy_key -C "lambda-instance-github-deploy" -N ""
   ```
   Add the contents of `github_deploy_key.pub` to GitHub → Settings → SSH and GPG
   keys. Keep both files out of git (they're not inside this repo, so nothing to
   gitignore, but don't move them in either).

## Per-session workflow

1. **Launch an instance** in the Lambda console. At launch, select the filesystem
   you created in step 1 to attach it — this is the one step that can't be done after
   the fact, so don't skip it.
2. **SSH in**, then clone (first time) or pull (subsequent sessions) this repo:
   ```bash
   git clone <this-repo-url> ~/LambdaLabs   # first time
   cd ~/LambdaLabs && git pull              # later sessions
   ```
3. **Bootstrap the project** you're working on (must be `source`d, not executed, so
   the venv activation and env vars persist in your shell):
   ```bash
   source bootstrap.sh PSUCSESafeRL
   ```
   First run for a project: creates the venv on the persistent filesystem and installs
   `requirements-extra.txt` (plus `setup-extra.sh` if present) — takes a minute or two.
   Every run after that: just activates the existing venv — a few seconds, no
   reinstalling.

   This step also wires up GitHub SSH auth from `/lambda/nfs/<fs-name>/ssh/github_deploy_key`
   if it's there, so `git clone`/`pull` over SSH just works without re-authenticating.
   **First session only**, that key won't exist yet — `bootstrap.sh` will print a
   reminder to `scp` it up once:
   ```bash
   scp -i id_ed25519 github_deploy_key ubuntu@<instance-ip>:/lambda/nfs/ml-persist/ssh/github_deploy_key
   ```
   Then re-run `source bootstrap.sh <project>`. Every session after that, the key is
   already on the filesystem and this is automatic.
4. Clone/pull your actual project code separately (this repo only holds the
   Lambda-specific setup files, not the RL/ML project code itself), e.g.:
   ```bash
   git clone git@github.com:thisisraghavkumar/PSUCSESafeRL.git ~/PSUCSESafeRL
   ```
5. Work. Checkpoints and datasets should be written to `$ML_CHECKPOINT_DIR` and
   `$ML_DATASET_DIR` (exported by `bootstrap.sh`) so they land on persistent storage.
   HuggingFace downloads automatically go to persistent storage too, since `HF_HOME` is
   set.
6. **Terminate the instance** from the console when done. The filesystem — and
   everything on it — persists; only compute billing stops. Storage keeps billing at
   $0.20/GB/month in the meantime.

## Adding a new project

1. Create `projects/<name>/requirements-extra.txt` — pip packages *not* already in
   Lambda Stack (skip torch, numpy, cuda-related packages; the venv inherits those).
2. Optional `projects/<name>/apt-extra.txt` — one system package per line (e.g.
   rendering libs); reinstalled fresh each session since it's cheap, not persisted.
3. Optional `projects/<name>/setup-extra.sh` — for anything beyond a plain pip
   install (e.g. installing a package from source). Receives the venv directory as
   `$1`. See `projects/PSUCSESafeRL/setup-extra.sh` for a worked example — prefer a
   plain `pip install <path>` over `pip install -e <path>` for anything cloned into a
   scratch directory, since an editable install keeps a path reference that would
   break once that ephemeral scratch dir is gone next session.
4. `source bootstrap.sh <name>` once to build the venv.

## Worked example: PSUCSESafeRL

`projects/PSUCSESafeRL/requirements-extra.txt` is converted from that project's own
`environment.yml` (a self-contained conda env), with `torch`, `torchvision`, `triton`,
`numpy`, `sympy`, `mpmath`, `networkx`, and the `nvidia-*-cu12`/`cuda-*` packages
stripped out — those come from Lambda Stack instead. `safety-gymnasium` is also left
out of the requirements file: that project's own Readme notes the PyPI release is
outdated and v1.2.0 needs installing from source, which `setup-extra.sh` handles.

The one real risk with this approach: if Lambda Stack's bundled torch/numpy versions
ever drift meaningfully from what a project was validated against (here,
`torch==2.10.0`, `numpy==1.23.5`), imports could break. `bootstrap.sh` stamps the
Python version at venv-creation time and warns (without failing) if a later session's
instance reports a different one — treat that warning as a cue to
`rm -rf /lambda/nfs/<fs>/envs/<project>` and rebuild if something stops working.

## Notes

- `bootstrap.sh` only exists to be `source`d — running it directly won't leave the
  venv activated or the env vars exported in your shell, and it will refuse to run
  that way.
- `id_ed25519` / `id_ed25519.pub` in this directory and `lambdalabs_api_key.txt` are
  gitignored — never commit them.
