# Mounted host directory: `/test/project`

- This is the project directory you invoked `claude-sandbox` from on the host.
- Mounted read-write at the same path inside the sandbox as on the host. Relative paths and `..` work the same on both sides.
- Changes persist on the host; everything outside any mounted directory lives only inside the container and disappears on `destroy`.
