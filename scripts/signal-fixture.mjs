// Used only by the offline scratch suite. No package-manager operations.
import { context, Transaction, attachSignals } from './bootstrap.mjs';
const tx = new Transaction(context()); tx.lock(); tx.validate();
if (process.argv.includes('--kill-restore')) {
  tx.checkpoint = phase => { if (phase === 'restore:keybindings') process.kill(process.pid, 'SIGKILL'); };
  await tx.recover(); throw Error('SIGKILL did not stop restoration');
}
const detach = attachSignals(tx);
try {
  await tx.run('/bin/bash', ['-c', 'printf damaged > "$HOME/.pi/agent/settings.json"; touch "$HOME/ready"; sleep 60; touch "$HOME/late-mutation"']);
} catch {
  await tx.recover();
  process.exitCode = 1;
} finally { tx.unlock(); detach(); }
