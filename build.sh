# Most clean installations or new users do have a local bin.
mkdir -p ~/.local/bin/

# Build linacs and store in bin.
sbcl \
  --eval '(require :asdf)' \
  --eval '(push #P"./" asdf:*central-registry*)' \
  --eval '(asdf:load-system :linacs-cli :force t)' \
  --eval '(sb-ext:save-lisp-and-die
             "linacs"
             :executable t
             :toplevel
             (lambda ()
               (linacs.core:main (rest sb-ext:*posix-argv*))))' \
&& ln -sf "$PWD/linacs" ~/.local/bin/linacs
