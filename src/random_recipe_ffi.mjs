export function start_view_transition(callback) {
  if (!document.startViewTransition) {
    callback()
    return;
  }

  document.startViewTransition(() => {
    callback();
  });
}
