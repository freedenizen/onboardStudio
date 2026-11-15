# Track definitions that ship with Onboard Studio

Each `.onboardtrack` file here is a circuit layout's start/finish, sectors and turn names, read
by every copy of the app behind the driver's own (`TrackLibrary.builtIn`, #584). A driver's own
definition for the same circuit and configuration always wins; changing a shipped one saves the
driver's own copy and leaves this folder alone.

Two kinds of file live here, and each says which it is in its `credit`:

- **LapViz's lines** (`credit` "LapViz (Mengal SRL), MIT"): the start/finish line, and the sector
  gates where it has them, of the European layouts in [LapViz](https://github.com/lapviz/LapViz.Telemetry)'s
  `circuits.json` at circuits the app's catalogue knows. No turn names: LapViz has none. They are
  © 2025–2026 Mengal SRL under the MIT licence in [`LICENSE-LapViz.md`](LICENSE-LapViz.md), which
  ships beside them. LapViz says its lines came from satellite imagery or recorded sessions; they
  are not checked against laps here. `Scripts/import-lapviz-tracks.py` writes them, and running it
  again replaces them and the rows between the `lapviz` markers below — never edit those by hand.
- **Contributed definitions**: everything else, **dedicated to the public domain under
  [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)** by the people who made it, so the
  app can ship it and anyone can reuse it. Only add a file you can dedicate that way: positions you
  measured yourself from your own driving, and the circuit's turn numbering, which is a fact. Never
  positions traced from map imagery or a circuit's map drawing, and never text copied from a map
  or a web site. A contributed definition for a layout LapViz also covers replaces LapViz's file:
  remove it, and the importer will not write it again while yours is there. How to make and
  contribute one is in
  [`docs/tracks-and-sectors.md`](../../../../docs/tracks-and-sectors.md#contributing-a-circuit-584).

Every file is listed below — `TrackLibraryBundleTests` fails for a file that is not — with who
made it and how.

| File | Circuit and layout | Made by | How |
|---|---|---|---|
<!-- lapviz:begin -->
| `q1025346.onboardtrack` | Cadwell Park | LapViz, “Cadwell Park” | start/finish from LapViz’s published gates, MIT |
| `q10313929.onboardtrack` | Kartódromo de Baltar | LapViz, “Kartódromo de Baltar” | start/finish from LapViz’s published gates, MIT |
| `q107264860.onboardtrack` | Autodromo del Levante | LapViz, “Autodromo del Levante” | start/finish from LapViz’s published gates, MIT |
| `q1074573.onboardtrack` | Croft Circuit | LapViz, “Croft Circuit” | start/finish from LapViz’s published gates, MIT |
| `q110822362.onboardtrack` | Three Sisters Race Circuit | LapViz, “Three Sisters Race Circuit” | start/finish from LapViz’s published gates, MIT |
| `q113027915.onboardtrack` | Circuito Internazionale d’Abruzzo | LapViz, “Abruzzo International Circuit” | start/finish from LapViz’s published gates, MIT |
| `q114825237.onboardtrack` | Motorpark Romania | LapViz, “Motorpark Romania” | start/finish from LapViz’s published gates, MIT |
| `q114929865.onboardtrack` | Kakucs Ring | LapViz, “Kakucs Ring (anticlockwise)” | start/finish from LapViz’s published gates, MIT |
| `q116800267.onboardtrack` | Autodromo di Lombardore | LapViz, “Autodromo di Lombardore” | start/finish from LapViz’s published gates, MIT |
| `q120299525.onboardtrack` | Circuit de Bresse | LapViz, “Circuit de Bresse” | start/finish from LapViz’s published gates, MIT |
| `q12290726.onboardtrack` | Dracon | LapViz, “Dragon Race Track” | start/finish from LapViz’s published gates, MIT |
| `q125775074.onboardtrack` | Pista azzurra | LapViz, “Pista Azzurra Jesolo” | start/finish from LapViz’s published gates, MIT |
| `q125776392.onboardtrack` | Pista Kart Planet | LapViz, “Kart Planet Busca” | start/finish from LapViz’s published gates, MIT |
| `q126950712.onboardtrack` | Circuit de La Châtre | LapViz, “Circuit de La Châtre” | start/finish from LapViz’s published gates, MIT |
| `q1321650.onboardtrack` | MotorLand Aragón | LapViz, “MotorLand Aragón” | start/finish from LapViz’s published gates, MIT |
| `q1347804.onboardtrack` | Misano World Circuit Marco Simoncelli | LapViz, “Misano World Circuit Marco Simoncelli” | start/finish from LapViz’s published gates, MIT |
| `q1374476.onboardtrack` | Euro-Ring | LapViz, “Euroring” | start/finish from LapViz’s published gates, MIT |
| `q152207-grand-prix.onboardtrack` | Nürburgring — Grand Prix | LapViz, “Nürburgring (Grand Prix)” | start/finish from LapViz’s published gates, MIT |
| `q152207-nordschleife.onboardtrack` | Nürburgring — Nordschleife | LapViz, “Nürburgring Nordschleife” | start/finish from LapViz’s published gates, MIT |
| `q152408.onboardtrack` | Hockenheimring | LapViz, “Hockenheimring” | start/finish from LapViz’s published gates, MIT |
| `q1583363.onboardtrack` | Mallory Park | LapViz, “Mallory Park” | start/finish from LapViz’s published gates, MIT |
| `q1585125-100.onboardtrack` | Snetterton Motor Racing Circuit — 100 | LapViz, “Snetterton (100)” | start/finish from LapViz’s published gates, MIT |
| `q1585125-200.onboardtrack` | Snetterton Motor Racing Circuit — 200 | LapViz, “Snetterton (200)” | start/finish from LapViz’s published gates, MIT |
| `q1585125-300.onboardtrack` | Snetterton Motor Racing Circuit — 300 | LapViz, “Snetterton (300)” | start/finish from LapViz’s published gates, MIT |
| `q16353023.onboardtrack` | Biķernieki Complex Sports Base | LapViz, “Biķernieku trase” | start/finish from LapViz’s published gates, MIT |
| `q16830288.onboardtrack` | Serres Racing Circuit | LapViz, “Serres Racing Circuit” | start/finish from LapViz’s published gates, MIT |
| `q168852.onboardtrack` | Rudskogen | LapViz, “Rudskogen Motorsenter” | start/finish from LapViz’s published gates, MIT |
| `q171313.onboardtrack` | Imola Circuit | LapViz, “Autodromo Enzo e Dino Ferrari (Imola)” | start/finish from LapViz’s published gates, MIT |
| `q171402-grand-prix.onboardtrack` | Silverstone Circuit — Grand Prix | LapViz, “Silverstone (Grand Prix)” | start/finish from LapViz’s published gates, MIT |
| `q171402-international.onboardtrack` | Silverstone Circuit — International | LapViz, “Silverstone (International)” | start/finish from LapViz’s published gates, MIT |
| `q171402-national.onboardtrack` | Silverstone Circuit — National | LapViz, “Silverstone (National)” | start/finish from LapViz’s published gates, MIT |
| `q171417.onboardtrack` | Monza Circuit | LapViz, “Autodromo Nazionale Monza” | start/finish from LapViz’s published gates, MIT |
| `q171424.onboardtrack` | Circuit Paul Ricard | LapViz, “Circuit Paul Ricard” | start/finish from LapViz’s published gates, MIT |
| `q171566.onboardtrack` | Red Bull Ring | LapViz, “Red Bull Ring” | start/finish from LapViz’s published gates, MIT |
| `q172851.onboardtrack` | Spa-Francochamps Circuit | LapViz, “Circuit de Spa-Francorchamps” | sectors from LapViz’s published gates, MIT |
| `q172868.onboardtrack` | Circuit Zolder | LapViz, “Circuit Zolder” | sectors from LapViz’s published gates, MIT |
| `q172876-club.onboardtrack` | Circuit de Nevers Magny-Cours — Club | LapViz, “Circuit de Nevers Magny-Cours (Club)” | start/finish from LapViz’s published gates, MIT |
| `q172876-grand-prix.onboardtrack` | Circuit de Nevers Magny-Cours — Grand Prix | LapViz, “Circuit de Nevers Magny-Cours (Grand Prix)” | start/finish from LapViz’s published gates, MIT |
| `q172879.onboardtrack` | Charade Circuit | LapViz, “Circuit de Charade” | start/finish from LapViz’s published gates, MIT |
| `q172880-grand-prix.onboardtrack` | Brands Hatch — Grand Prix | LapViz, “Brands Hatch (Grand Prix)” | start/finish from LapViz’s published gates, MIT |
| `q172880-indy.onboardtrack` | Brands Hatch — Indy | LapViz, “Brands Hatch (Indy)” | start/finish from LapViz’s published gates, MIT |
| `q172888.onboardtrack` | Dijon-Prenois | LapViz, “Circuit Dijon-Prenois” | start/finish from LapViz’s published gates, MIT |
| `q173083.onboardtrack` | Circuit Zandvoort | LapViz, “Circuit Zandvoort” | start/finish from LapViz’s published gates, MIT |
| `q173202.onboardtrack` | Donington Park | LapViz, “Donington Park” | start/finish from LapViz’s published gates, MIT |
| `q174004.onboardtrack` | Sirius Autodrom | LapViz, “Sochi Autodrom” | start/finish from LapViz’s published gates, MIT |
| `q1878589.onboardtrack` | Lydden Hill Race Circuit | LapViz, “Lydden Hill Race Circuit” | start/finish from LapViz’s published gates, MIT |
| `q1888287-national.onboardtrack` | Mondello Park — National | LapViz, “Mondello Park (National)” | start/finish from LapViz’s published gates, MIT |
| `q1888287-short.onboardtrack` | Mondello Park — Short | LapViz, “Mondello Park (Short)” | start/finish from LapViz’s published gates, MIT |
| `q1888287.onboardtrack` | Mondello Park | LapViz, “Mondello Park” | start/finish from LapViz’s published gates, MIT |
| `q194201.onboardtrack` | Padborg Park | LapViz, “Padborg Park” | start/finish from LapViz’s published gates, MIT |
| `q194546.onboardtrack` | Ring Djursland | LapViz, “Ring Djursland” | start/finish from LapViz’s published gates, MIT |
| `q2065051.onboardtrack` | Autodromo di Franciacorta | LapViz, “Autodromo di Franciacorta” | start/finish from LapViz’s published gates, MIT |
| `q2215233.onboardtrack` | Circuit du Val de Vienne | LapViz, “Circuit du Val de Vienne” | start/finish from LapViz’s published gates, MIT |
| `q222686.onboardtrack` | Masaryk Circuit | LapViz, “Automotodrom Brno” | start/finish from LapViz’s published gates, MIT |
| `q2250260.onboardtrack` | Autodromo Riccardo Paletti | LapViz, “Autodromo Riccardo Paletti (Varano)” | start/finish from LapViz’s published gates, MIT |
| `q2465788.onboardtrack` | Thruxton Circuit | LapViz, “Thruxton Circuit” | start/finish from LapViz’s published gates, MIT |
| `q2538310.onboardtrack` | Wachauring | LapViz, “Wachauring Melk” | start/finish from LapViz’s published gates, MIT |
| `q2623403.onboardtrack` | Alastaro Circuit | LapViz, “Alastaro Circuit” | start/finish from LapViz’s published gates, MIT |
| `q2630372.onboardtrack` | Top Gear test track | LapViz, “Dunsfold Park” | start/finish from LapViz’s published gates, MIT |
| `q2654550-international-sportscar.onboardtrack` | Rockingham Motor Speedway — International Sportscar | LapViz, “Rockingham (International Sportscar)” | start/finish from LapViz’s published gates, MIT |
| `q2654550-national-anticlockwise.onboardtrack` | Rockingham Motor Speedway — National, anticlockwise | LapViz, “Rockingham (National, anticlockwise)” | start/finish from LapViz’s published gates, MIT |
| `q2654550-national-clockwise.onboardtrack` | Rockingham Motor Speedway — National, clockwise | LapViz, “Rockingham (National, clockwise)” | start/finish from LapViz’s published gates, MIT |
| `q2654550-oval.onboardtrack` | Rockingham Motor Speedway — Oval | LapViz, “Rockingham (Oval)” | start/finish from LapViz’s published gates, MIT |
| `q2973963.onboardtrack` | Circuit Carole | LapViz, “Circuit Carole” | start/finish from LapViz’s published gates, MIT |
| `q2973985.onboardtrack` | Circuit de Chambley | LapViz, “Circuit de Chambley” | start/finish from LapViz’s published gates, MIT |
| `q2973992.onboardtrack` | Circuit de Haute Saintonge | LapViz, “Circuit de Haute Saintonge” | start/finish from LapViz’s published gates, MIT |
| `q2974006.onboardtrack` | Circuit de Lédenon | LapViz, “Circuit de Lédenon” | start/finish from LapViz’s published gates, MIT |
| `q2974025.onboardtrack` | Circuit de Croix-en-Ternois | LapViz, “Circuit de Croix-en-Ternois” | start/finish from LapViz’s published gates, MIT |
| `q2974031.onboardtrack` | Circuit du Luc | LapViz, “Circuit du Var” | start/finish from LapViz’s published gates, MIT |
| `q3412171.onboardtrack` | Pôle Mécanique Alès Cévennes | LapViz, “Pôle Mécanique Alès Cévennes” | start/finish from LapViz’s published gates, MIT |
| `q3630487.onboardtrack` | Autodromo di Mores | LapViz, “Autodromo di Mores” | start/finish from LapViz’s published gates, MIT |
| `q427654.onboardtrack` | Automotodróm Slovakia Ring | LapViz, “Slovakiaring” | start/finish from LapViz’s published gates, MIT |
| `q4304395.onboardtrack` | Autodrom Moscow | LapViz, “ADM Raceway” | start/finish from LapViz’s published gates, MIT |
| `q4696439.onboardtrack` | Ahvenisto Race Circuit | LapViz, “Ahvenisto Race Circuit” | start/finish from LapViz’s published gates, MIT |
| `q4763391-club.onboardtrack` | Anglesey Circuit — Club | LapViz, “Anglesey Circuit (Club)” | start/finish from LapViz’s published gates, MIT |
| `q4763391-coastal.onboardtrack` | Anglesey Circuit — Coastal | LapViz, “Anglesey Circuit (Coastal)” | start/finish from LapViz’s published gates, MIT |
| `q4763391-international.onboardtrack` | Anglesey Circuit — International | LapViz, “Anglesey Circuit (International)” | start/finish from LapViz’s published gates, MIT |
| `q4763391-national.onboardtrack` | Anglesey Circuit — National | LapViz, “Anglesey Circuit (National)” | start/finish from LapViz’s published gates, MIT |
| `q48780398.onboardtrack` | Tazio Nuvolari Circuit | LapViz, “Tazio Nuvolari Circuit (full)” | start/finish from LapViz’s published gates, MIT |
| `q4983421.onboardtrack` | Buckmore Park Kart Circuit | LapViz, “Buckmore Park Kart Circuit” | start/finish from LapViz’s published gates, MIT |
| `q5050030.onboardtrack` | Castle Combe Circuit | LapViz, “Castle Combe Circuit” | start/finish from LapViz’s published gates, MIT |
| `q524404.onboardtrack` | Knockhill Racing Circuit | LapViz, “Knockhill Racing Circuit” | start/finish from LapViz’s published gates, MIT |
| `q5407985.onboardtrack` | Circuito de Almería | LapViz, “Circuito de Almería” | start/finish from LapViz’s published gates, MIT |
| `q55371593.onboardtrack` | Circuit of Folembray | LapViz, “Circuit de Folembray” | start/finish from LapViz’s published gates, MIT |
| `q567770.onboardtrack` | Sachsenring | LapViz, “Sachsenring” | start/finish from LapViz’s published gates, MIT |
| `q570236.onboardtrack` | Circuito Vasco Sameiro | LapViz, “Circuito Vasco Sameiro (Braga)” | start/finish from LapViz’s published gates, MIT |
| `q5766979.onboardtrack` | Nemuno Žiedas | LapViz, “Nemuno žiedas” | start/finish from LapViz’s published gates, MIT |
| `q609448.onboardtrack` | Circuit Pau-Arnos | LapViz, “Circuit Pau-Arnos” | start/finish from LapViz’s published gates, MIT |
| `q6319353.onboardtrack` | Jyllands-Ringen | LapViz, “FDM Jyllandsringen” | start/finish from LapViz’s published gates, MIT |
| `q6717891.onboardtrack` | MSR Houston | LapViz, “MSR Houston (MSRH)” | start/finish from LapViz’s published gates, MIT |
| `q6918074.onboardtrack` | Motopark Raceway | LapViz, “Motopark Raceway” | start/finish from LapViz’s published gates, MIT |
| `q699372.onboardtrack` | EuroSpeedway Lausitz | LapViz, “Lausitzring (Grand Prix)” | start/finish from LapViz’s published gates, MIT |
| `q700121.onboardtrack` | Salzburgring | LapViz, “Salzburgring” | start/finish from LapViz’s published gates, MIT |
| `q7161930.onboardtrack` | Pembrey Circuit | LapViz, “Pembrey Circuit” | start/finish from LapViz’s published gates, MIT |
| `q7488996.onboardtrack` | Shannonville Motorsport Park | LapViz, “Shannonville Motorsport Park” | sectors from LapViz’s published gates, MIT |
| `q782455.onboardtrack` | Mugello Circuit | LapViz, “Mugello Circuit” | start/finish from LapViz’s published gates, MIT |
| `q786413.onboardtrack` | Autodrom Sosnová | LapViz, “Autodrom Sosnová” | start/finish from LapViz’s published gates, MIT |
| `q786418.onboardtrack` | Autodrom Most | LapViz, “Autodrom Most” | start/finish from LapViz’s published gates, MIT |
| `q786432.onboardtrack` | ACI Vallelunga Circuit | LapViz, “Autodromo di Vallelunga” | start/finish from LapViz’s published gates, MIT |
| `q787936.onboardtrack` | Automotodrom Grobnik | LapViz, “Automotodrom Grobnik” | start/finish from LapViz’s published gates, MIT |
| `q789427.onboardtrack` | Autódromo Internacional do Algarve | LapViz, “Autódromo Internacional do Algarve” | start/finish from LapViz’s published gates, MIT |
| `q7944475.onboardtrack` | Vålerbanen | LapViz, “Valerbanen” | start/finish from LapViz’s published gates, MIT |
| `q813859-gt.onboardtrack` | Bedford Autodrome — GT | LapViz, “Bedford Autodrome (GT)” | start/finish from LapViz’s published gates, MIT |
| `q813859-south-west.onboardtrack` | Bedford Autodrome — South West | LapViz, “Bedford Autodrome (South West)” | start/finish from LapViz’s published gates, MIT |
| `q8346365.onboardtrack` | Circuit d'Alcarràs | LapViz, “Circuit d'Alcarràs” | start/finish from LapViz’s published gates, MIT |
| `q836417.onboardtrack` | Motorsport Arena Oschersleben | LapViz, “Motorsport Arena Oschersleben” | start/finish from LapViz’s published gates, MIT |
| `q843925.onboardtrack` | TT Circuit Assen | LapViz, “TT Circuit Assen” | start/finish from LapViz’s published gates, MIT |
| `q863357.onboardtrack` | Bilster Berg | LapViz, “Bilster Berg” | start/finish from LapViz’s published gates, MIT |
| `q867548.onboardtrack` | Circuit Paul Armagnac | LapViz, “Circuit Paul Armagnac” | start/finish from LapViz’s published gates, MIT |
| `q867557.onboardtrack` | Circuito de Albacete | LapViz, “Circuito de Albacete” | start/finish from LapViz’s published gates, MIT |
| `q894749.onboardtrack` | Botniaring Racing Circuit | LapViz, “Botniaring” | start/finish from LapViz’s published gates, MIT |
| `q928721.onboardtrack` | Bugatti Circuit | LapViz, “Circuit Bugatti (Le Mans)” | start/finish from LapViz’s published gates, MIT |
| `q9360123.onboardtrack` | Tor Poznań | LapViz, “Tor Poznań” | start/finish from LapViz’s published gates, MIT |
| `q936985.onboardtrack` | Circuit Jules Tacheny Mettet | LapViz, “Circuit Jules Tacheny Mettet” | sectors from LapViz’s published gates, MIT |
| `q953716.onboardtrack` | Goodwood Circuit | LapViz, “Goodwood Motor Circuit” | start/finish from LapViz’s published gates, MIT |
| `q997133-foster-s.onboardtrack` | Oulton Park — Foster's | LapViz, “Oulton Park (Foster's)” | start/finish from LapViz’s published gates, MIT |
| `q997133-international.onboardtrack` | Oulton Park — International | LapViz, “Oulton Park (International)” | start/finish from LapViz’s published gates, MIT |
| `q997133-island.onboardtrack` | Oulton Park — Island | LapViz, “Oulton Park (Island)” | start/finish from LapViz’s published gates, MIT |
<!-- lapviz:end -->
