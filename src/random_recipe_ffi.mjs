export function start_view_transition(callback) {
  document.startViewTransition(() => {
    callback();
  });
}
