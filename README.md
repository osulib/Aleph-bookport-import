# Bookport import popis  (osu.cz, 20201008)

## importní skript: /exlibris/aleph/matyas/bookport_import.mat

**Stáhne** se xml feed se záznamy aktuálně nabízené kolekce Bookport.
1. srovnají se ID bookportu (001) s daty v Alephu (zde pole BOO KP). Nenalezené záznamy se smažou (nad určitý počet nemažou, mlže být chyba)

2. Hledá se **shoda ID bookportu** v katalogu. U nalezených záznamů, které v katalogu jsou, se updatuje pole 856 - link na plný text na bookport.cz

3. Nové záznamy jsou srovnány s katalogem dle ISBN. Nalezne-li se shoda, jde o **tištěné verze nově importovaných e-knih**. Do těchto záznamů se doplní pole BAS (ebooks - bookport), ID bookportu (pole BOO KP), URL na plný text (pole 856) a pole 856 s odkazem na návod. Je-li totéž ISBN u více záznamů, je upozorněn administrátor ve výsledku importu. Zde se při updatu využívá fix BOKP2 a vlastní fix procedura.

4. Zcela **nové záznamy** jsou před importem upraveny fixem BOOKP a vlastní fix procedurou. Lze jej spustit i ručně z katalogu (upravit záznam programem). Provádí se následující úpravy/doplnění
    - ID bookportu se přidá do vlastního pole BOO KP. Dále se u nových dá do pole 001, ale s prefixem bookport. Např. 001 L bookport145678
    - sigla OSD001 se přidá do pole 040 podpole d
    - pole FMT EB
    - pole 007 se nahradí univerzální hodnotou pro remote access: 007 L cr-|n|||||||||
    - do pole 008 se doplní online verze (hodnota o na pozici 23)
    - pokud se dle 072 v importu najde fikce, doplní se "1" do pole 008 jako beletrie, podobně "j" do čten. určení, je-li 072 fikce pro mládež (JUV)
    - do pole 245 se doplní diakritika, do pole 264 rovněž diakrtika a zpravidla chybějící podpole a je přidáno s hodnotou "[Místo vydání není známé] :"
    - z pole 520 se odstraní html entity
    - pole 856 k linku na plný text se přidá (nahradí) podpole y "Plný text PDF (Bookport)" a podpole 4 "N". Přidá se nové podpole 856 s odkazem na návod: 85642 L $$uhttps://dokumenty.osu.cz/knihovna/bookport.pdf$$y* Návod pro Bookport$$4N
    - pokud má záznam tištěné isbn (q(print)), dohledá se přes Z39.50 záznam v Souborném katalogu. Pokud se najde: 
            přidají se dle Souborného kat. pole věcného a zčásti jmenného popisu: 043, 045, 072 7, 080, 60x, 61x, 648 7, 65007, 651 7, 655 7
            nahradí se stávající pole: 1xx, 7xx, 041 a 240
            Věcný popis má zpravidla slovník MRF pro 080 a vždy Národní autority pro věcný popis 6xx.
    - věcná hesla stažená z Bookportu se pokusí navázat na slovník OU: tezou. Pomocí x-serveru ověří heslo a pokud najde, přidá nové pole 65007 s hodnotou hesla a podpolem 2 tezou (naváže se na autority)        
    - vždy se přidá pole 655 7 L $$aelektronické knihy$$2tezou  (většinou jde o RDA, kde je pole 655 povinné)
    - přidá se pole IST s aktuálním datem v podpoli a (bez prefixu).  Slouží pro výběr do novinek.
    
**Fix **pro update pole 856 u existujících: /exlibris/aleph/matyas/vlastni_fixy/osu_import_eb_bookport856.pl  (upraví jen pole 856 40)
Fix import nových: /exlibris/aleph/matyas/vlastni_fixy/osu_import_eb_bookport.pl  (provádí úpravy dle bodu 4 výše)
Oba jsou symlinkovány z adresáře $aleph_exe, kde je Aleph dohledává

Přidány 2 nové fixy pro update 856 a nový import: osu01/tab/tab_fix:
`!nove zaznamy`
`BOOKP osu_import_eb_bookport.pl`
`BOOKP fix_doc_tag_008_open_date`
`BOOKP fix_doc_non_filing_ind2`
`BOOKP fix_doc_ref_1`
`BOOKP fix_doc_lng_from_bib`
`BOOKP fix_doc_sort`
`BOOKP fix_doc_sort_505`
`!update pole 856`
`BOKP2 osu_import_eb_bookport856.pl`


### Pravidelné spouštění - job_list
Spouští se 2x měsíčně, 5. a 20. den v měsíci. Jelikož to takto joblist nastavit neumí, je nad tím pomocný skript /exlibris/aleph/matyas/bookport_import4joblist.sh (zde se ověří, zda je 5. nebo 20. den)

