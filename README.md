Originally from @JD:
<br />
https://gist.github.com/johnd0e/5110ddfb3291928a7f484cd38f23ff87/
<br />
https://forum.farmanager.com/viewtopic.php?t=7988
<br />
.. with my and @Xer0X's changes

changes are:
* Retentive, i.e. reopened on the same object (=table) subelement
* Ability to navigate by given path, 
for example this:
lua`:LE(_G, nil, nil, nil, {"Area"})`
.. will open the `"_G=>Area`" table
and this:
lua: `LE(_G, nil, nil, nil, {"far", "Colors"})`
.. will open the `{_G=>far=>Colors}` table
* Not like in original code exiting on Escape, 
this modification exits on Escape, goes back on BackSpace

