-- Seed: výchozí soutěž 'IC Office Challenge' + 15 otázek převzatých
-- z původního defaultQuestions v index.html. Spustit jednou po 0001.

insert into public.challenge (slug, title, intro_text, question_count, time_limit_minutes)
values (
  'default',
  'IC Office Challenge',
  'Krátká soutěž pro studenty, mechaniky i mistry. Čeká tě 15 otázek na 15 minut. Rozhoduje počet správných odpovědí. Při shodě bodů rozhoduje rychlejší čas. Vyhodnocení soutěže proběhne na konci dne.',
  15,
  15
)
on conflict (slug) do nothing;

-- Otázky 1–15
with c as (select id from public.challenge where slug = 'default')
insert into public.questions (challenge_id, position, text, options, correct, practical)
select c.id, v.position, v.text, v.options, v.correct, v.practical from c, (values
  (1,
   'Co přesně je IC Office a kolik stojí přibližně na den?',
   jsonb_build_array(
     'zakázkový a fakturační systém pro profesionální vedení autoservisu / zhruba 23 Kč na den',
     'účetní software pro fakturaci a daně / zhruba 120 Kč na den',
     'aplikace pro diagnostiku vozidel / zhruba 80 Kč na den',
     'rozšířený balík Microsoft 365 / zhruba 15 Kč na den'),
   'zakázkový a fakturační systém pro profesionální vedení autoservisu / zhruba 23 Kč na den',
   false),
  (2,
   'Jak bys nejlépe popsal IC Office kolegovi?',
   jsonb_build_array(
     'program na vedení autoservisu',
     'aplikace pro objednávání dílů',
     'něco jako Excel pro auta',
     'program hlavně na fakturaci'),
   'program na vedení autoservisu',
   false),
  (3,
   'Při příjmu vozidla do servisu je největší ztráta času typicky:',
   jsonb_build_array(
     'ruční vypisování zakázkového listu',
     'přivítání zákazníka',
     'zaparkování vozu',
     'hledání velkého technického průkazu'),
   'ruční vypisování zakázkového listu',
   false),
  (4,
   'V čem pomáhá IC Office majitelům autoservisu?',
   jsonb_build_array(
     'šetří čas při každodenní práci v autoservisu',
     'stanovuje cenu opravy za mechanika',
     'zrychluje samotnou mechanickou opravu',
     'hledá nové zaměstnance do servisu'),
   'šetří čas při každodenní práci v autoservisu',
   false),
  (5,
   'Jaký je hlavní přínos načtení informací o vozidle pomocí fotografie VIN kódu?',
   jsonb_build_array(
     'automatické vyplnění zakázkového listu',
     'automatické vyřešení závady',
     'zrychlení diagnostiky motoru',
     'eliminace překlepu'),
   'automatické vyplnění zakázkového listu',
   false),
  (6,
   'Vede IC Office historii oprav vozidla?',
   jsonb_build_array(
     'Ano, vede ji a umí ji poslat i e-mailem majiteli vozu',
     'Ano, ale jen v papírové podobě',
     'Ne, historii oprav nevede',
     'Jen u vozidel registrovaných v České republice'),
   'Ano, vede ji a umí ji poslat i e-mailem majiteli vozu',
   false),
  (7,
   'Jaký přínos má přehled zakázek v systému?',
   jsonb_build_array(
     'lepší organizace práce a plánování',
     'automatická oprava vozidel',
     'snížení počtu zákazníků',
     'eliminace potřeby mechaniků'),
   'lepší organizace práce a plánování',
   false),
  (8,
   'Splňuje systém IC Office právní legislativu?',
   jsonb_build_array(
     'Ano, včetně GDPR',
     'Jen GDPR',
     'Ne, legislativu neřeší',
     'Jen požadavky České obchodní inspekce'),
   'Ano, včetně GDPR',
   false),
  (9,
   'Jaké riziko přináší ruční zadávání údajů o vozidle?',
   jsonb_build_array(
     'vznik chyb a překlepů v informacích o vozidle',
     'zrychlení procesu',
     'vyšší přesnost',
     'snížení administrativy'),
   'vznik chyb a překlepů v informacích o vozidle',
   false),
  (10,
   'Co má největší vliv na schopnost servisu odbavit více zakázek?',
   jsonb_build_array(
     'rychlá práce s informacemi a daty',
     'vyšší hlasitost rádia',
     'větší pracovní stůl',
     'delší pracovní doba'),
   'rychlá práce s informacemi a daty',
   false),
  (11,
   'Podle jakého údaje o vozidle nejpřesněji vybereme správný náhradní díl?',
   jsonb_build_array(
     'VIN vozidla',
     'barva vozidla',
     'kód motoru',
     'rok výroby'),
   'VIN vozidla',
   false),
  (12,
   'Je systém IC Office online?',
   jsonb_build_array(
     'Ano',
     'Ne, je to lokální instalace',
     'Jen na tabletu',
     'Jen pro velké autoservisy'),
   'Ano',
   false),
  (13,
   'Co nejčastěji zpomaluje práci v autoservisu?',
   jsonb_build_array(
     'dohledávání informací místo samotné práce',
     'samotná oprava',
     'kontrola vozidla',
     'příchod zákazníka'),
   'dohledávání informací místo samotné práce',
   false),
  (14,
   'Kdo vymyslel IC Office?',
   jsonb_build_array(
     'majitel autoservisu',
     'ministerstvo školství',
     'ajťák',
     'účetní'),
   'majitel autoservisu',
   false),
  (15,
   'Kolik autoservisů v ČR používá IC Office?',
   jsonb_build_array('170','370','700','70'),
   '700',
   true)
) as v(position, text, options, correct, practical)
on conflict (challenge_id, position) do nothing;
