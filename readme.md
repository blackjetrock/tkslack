# tkslack

A simple refined minimalist slacking experience.

### Install

First grab a token from https://api.slack.com/custom-integrations/legacy-tokens then do this:

```bash
echo "xxx-1111-2222-3333-ABC" > ~/.tkslack # replace with your token
brew cask install https://raw.githubusercontent.com/nickbarth/tkslack/master/tkslack.rb
```

Try it out: 

```bash
echo "xxx-1111-2222-3333-ABC" > ~/.tkslack # replace with your token
wish <(curl -s https://raw.githubusercontent.com/nickbarth/tkslack/master/main.tcl)
```

![screenshot](https://raw.githubusercontent.com/nickbarth/tkslack/master/)

### Hotkeys 

<table>
  <tr>
    <td>⌘ k</td><td>Switch Channel</td>
  </tr>
  <tr>
    <td>Enter</td><td>Send Message</td>
  </tr>
</table>

### License
WTFPL &copy; 2019 Nick Barth
