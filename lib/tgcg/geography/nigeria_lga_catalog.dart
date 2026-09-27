// Nationwide LGA catalogue used by the geographic command workspace.
// 774 LGA names; state IDs match GeographyRegistry state IDs.
const Map<String, List<String>> nigeriaLgaSlugsByStateId = {
  'AB': ['aba-north', 'aba-south', 'arochukwu', 'bende', 'ikwuano', 'isiala-ngwa-north', 'isiala-ngwa-south', 'isuikwuato', 'obingwa', 'ohafia', 'osisioma', 'ugwunagbo', 'ukwa-west', 'ukwa-east', 'umu-nneochi', 'umuahia-south', 'umuahia-north'],
  'AD': ['demsa', 'fufore', 'ganye', 'girei', 'gombi', 'guyuk', 'hong', 'jada', 'lamurde', 'madagali', 'maiha', 'mayo-belwa', 'michika', 'mubi-north', 'mubi-south', 'numan', 'shelleng', 'song', 'toungo', 'yola-north', 'yola-south'],
  'AK': ['abak', 'eastern-obolo', 'eket', 'esit-eket', 'essien-udim', 'etim-ekpo', 'etinan', 'ibeno', 'ibesikpo-asutan', 'ibiono-ibom', 'ika', 'ikono', 'ikot-abasi', 'ikot-ekpene', 'ini', 'itu', 'mbo', 'mkpat-enin', 'nsit-atai', 'nsit-ibom', 'nsit-ubium', 'obot-akara', 'okobo', 'onna', 'oron', 'oruk-anam', 'udung-uko', 'ukanafun', 'uruan', 'urue-offong-oruko', 'uyo'],
  'AN': ['aguata', 'anambra-east', 'anambra-west', 'anaocha', 'awka-north', 'awka-south', 'ayamelum', 'dunukofia', 'ekwusigo', 'idemili-north', 'idemili-south', 'ihiala', 'njikoka', 'nnewi-north', 'nnewi-south', 'ogbaru', 'onitsha-north', 'onitsha-south', 'orumba-south', 'orumba-north', 'oyi'],
  'FCT': ['abaji', 'abuja-municipal', 'bwari', 'gwagwalada', 'kuje', 'kwali'],
  'BA': ['alkaleri', 'bauchi', 'bogoro', 'dambam', 'darazo', 'dass', 'gamawa', 'ganjuwa', 'giade', 'itas-gadau', 'jama\'are', 'katagum', 'kirfi', 'misau', 'ningi', 'shira', 'tafawa-balewa', 'toro', 'warji', 'zaki'],
  'BY': ['brass', 'ekeremor', 'kolokuma-opokuma', 'nembe', 'ogbia', 'sagbama', 'southern-ijaw', 'yenagoa'],
  'BN': ['ado', 'agatu', 'apa', 'buruku', 'gboko', 'guma', 'gwer-east', 'gwer-west', 'katsina-ala', 'konshisha', 'kwande', 'logo', 'makurdi', 'obi', 'ogbadibo', 'ohimini', 'oju', 'okpokwu', 'otukpo', 'tarka', 'ukum', 'ushongo', 'vandeikya'],
  'BO': ['abadam', 'askira-uba', 'bama', 'bayo', 'biu', 'chibok', 'damboa', 'dikwa', 'gubio', 'guzamala', 'gwoza', 'hawul', 'jere', 'kaga', 'kala-balge', 'konduga', 'kukawa', 'kwaya-kusar', 'mafa', 'magumeri', 'maiduguri', 'marte', 'mobbar', 'monguno', 'ngala', 'nganzai', 'shani'],
  'CR': ['abi', 'akamkpa', 'akpabuyo', 'bakassi', 'bekwarra', 'biase', 'boki', 'calabar-municipality', 'calabar-south', 'etung', 'ikom', 'obanliku', 'obubra', 'obudu', 'odukpani', 'ogoja', 'yakurr', 'yala'],
  'DE': ['aniocha-north', 'aniocha-south', 'bomadi', 'burutu', 'ethiope-west', 'ethiope-east', 'ika-north-east', 'ika-south', 'isoko-north', 'isoko-south', 'ndokwa-east', 'ndokwa-west', 'okpe', 'oshimili-north', 'oshimili-south', 'patani', 'sapele', 'udu', 'ughelli-north', 'ughelli-south', 'ukwuani', 'uvwie', 'warri-north', 'warri-south', 'warri-south-west'],
  'EB': ['abakaliki', 'afikpo-south', 'afikpo-north', 'ebonyi', 'ezza-north', 'ezza-south', 'ikwo', 'ishielu', 'ivo', 'izzi', 'ohaozara', 'ohaukwu', 'onicha'],
  'ED': ['akoko-edo', 'egor', 'esan-central', 'esan-north-east', 'esan-south-east', 'esan-west', 'etsako-west', 'etsako-central', 'etsako-east', 'igueben', 'ikpoba-okha', 'oredo', 'orhionmwon', 'ovia-north-east', 'ovia-south-west', 'owan-east', 'owan-west', 'uhunmwode'],
  'EK': ['ado-ekiti', 'efon', 'ekiti-east', 'ekiti-south-west', 'ekiti-west', 'emure', 'gbonyin', 'ido-osi', 'ijero', 'ikere', 'ikole', 'ilejemeje', 'irepodun-ifelodun', 'ise-orun', 'moba', 'oye'],
  'EN': ['aninri', 'awgu', 'enugu-east', 'enugu-north', 'enugu-south', 'ezeagu', 'igbo-etiti', 'igbo-eze-north', 'igbo-eze-south', 'isi-uzo', 'nkanu-east', 'nkanu-west', 'nsukka', 'oji-river', 'udenu', 'udi', 'uzo-uwani'],
  'GO': ['akko', 'balanga', 'billiri', 'dukku', 'funakaye', 'gombe', 'kaltungo', 'kwami', 'nafada', 'shongom', 'yalmaltu-deba'],
  'IM': ['aboh-mbaise', 'ahiazu-mbaise', 'ehime-mbano', 'ezinihitte-mbaise', 'ideato-north', 'ideato-south', 'ihitte-uboma', 'ikeduru', 'isiala-mbano', 'isu', 'mbaitoli', 'ngor-okpala', 'njaba', 'nkwerre', 'nwangele', 'obowo', 'oguta', 'ohaji-egbema', 'okigwe', 'onuimo', 'orlu', 'orsu', 'oru-east', 'oru-west', 'owerri-north', 'owerri-urban', 'owerri-west'],
  'JI': ['auyo', 'babura', 'birnin-kudu', 'birniwa', 'buji', 'dutse', 'gagarawa', 'garki', 'gumel', 'guri', 'gwaram', 'gwiwa', 'hadejia', 'jahun', 'kafin-hausa', 'kaugama', 'kazaure', 'kirika-samma', 'kiyawa', 'maigatari', 'malam-madori', 'miga', 'ringim', 'roni', 'sule-tankarkar', 'taura', 'yankwashi'],
  'KD': ['birnin-gwari', 'chikun', 'giwa', 'igabi', 'ikara', 'jaba', 'jema\'a', 'kachia', 'kaduna-north', 'kaduna-south', 'kagarko', 'kajuru', 'kaura', 'kauru', 'kubau', 'kudan', 'lere', 'makarfi', 'sabon-gari', 'sanga', 'soba', 'zangon-kataf', 'zaria'],
  'KN': ['ajingi', 'albasu', 'bagwai', 'bebeji', 'bichi', 'bunkure', 'dala', 'danbata', 'dawaki-kudu', 'dawaki-tofa', 'doguwa', 'fagge', 'gabasawa', 'garko', 'garun-malam', 'gaya', 'gezawa', 'gwale', 'gwarzo', 'kabo', 'kano-municipal', 'karaye', 'kibiya', 'kiru', 'kumbotso', 'kunchi', 'kura', 'madobi', 'makoda', 'minjibir', 'nasarawa', 'rano', 'rimin-gado', 'rogo', 'shanono', 'sumaila', 'takai', 'tarauni', 'tofa', 'tsanyawa', 'tudun-wada', 'ungogo', 'warawa', 'wudil'],
  'KT': ['bakori', 'batagarawa', 'batsari', 'baure', 'bindawa', 'charanchi', 'dan-musa', 'dandume', 'danja', 'daura', 'dutsi', 'dutsin-ma', 'faskari', 'funtua', 'ingawa', 'jibia', 'kafur', 'kaita', 'kankara', 'kankia', 'katsina', 'kurfi', 'kusada', 'mai\'adua', 'malumfashi', 'mani', 'mashi', 'matazu', 'musawa', 'rimi', 'sabuwa', 'safana', 'sandamu', 'zango'],
  'KE': ['aliero', 'arewa', 'argungu', 'augie', 'bagudo', 'birnin-kebbi', 'bunza', 'dandi', 'fakai', 'gwandu', 'jega', 'kalgo', 'koko-besse', 'maiyama', 'ngaski', 'sakaba', 'shanga', 'suru', 'wasagu-danko', 'yauri', 'zuru'],
  'KO': ['adavi', 'ajaokuta', 'ankpa', 'bassa', 'dekina', 'ibaji', 'idah', 'igalamela-odolu', 'ijumu', 'kabba-bunu', 'koton-karfe', 'lokoja', 'mopa-muro', 'ofu', 'ogori-magongo', 'okehi', 'okene', 'olamaboro', 'omala', 'yagba-east', 'yagba-west'],
  'KW': ['asa', 'baruten', 'edu', 'ekiti', 'ifelodun', 'ilorin-east', 'ilorin-south', 'ilorin-west', 'irepodun', 'isin', 'kaiama', 'moro', 'offa', 'oke-ero', 'oyun', 'patigi'],
  'LA': ['agege', 'ajeromi-ifelodun', 'alimosho', 'amuwo-odofin', 'apapa', 'badagry', 'epe', 'eti-osa', 'ibeju-lekki', 'ifako-ijaye', 'ikeja', 'ikorodu', 'kosofe', 'lagos-island', 'lagos-mainland', 'mushin', 'ojo', 'oshodi-isolo', 'somolu', 'surulere'],
  'NA': ['akwanga', 'awe', 'doma', 'karu', 'keana', 'keffi', 'kokona', 'lafia', 'nasarawa', 'nasarawa-eggon', 'obi', 'toto', 'wamba'],
  'NI': ['agaie', 'agwara', 'bida', 'borgu', 'bosso', 'chanchaga', 'edatti', 'gbako', 'gurara', 'katcha', 'kontagora', 'lapai', 'lavun', 'magama', 'mariga', 'mashegu', 'mokwa', 'munya', 'paikoro', 'rafi', 'rijau', 'shiroro', 'suleja', 'tafa', 'wushishi'],
  'OG': ['abeokuta-north', 'abeokuta-south', 'ado-odo-ota', 'ewekoro', 'ifo', 'ijebu-east', 'ijebu-north', 'ijebu-north-east', 'ijebu-ode', 'ikenne', 'imeko-afon', 'ipokia', 'obafemi-owode', 'odeda', 'odogbolu', 'ogun-water-side', 'remo-north', 'sagamu', 'yewa-egbado-north', 'yewa-egbado-south'],
  'ON': ['akoko-north-east', 'akoko-north-west', 'akoko-south-east', 'akoko-south-west', 'akure-north', 'akure-south', 'ese-odo', 'idanre', 'ifedore', 'ilaje', 'ileoluji-okeigbo', 'irele', 'odigbo', 'okitipupa', 'ondo-east', 'ondo-west', 'ose', 'owo'],
  'OS': ['atakumosa-east', 'atakumosa-west', 'ayedaade', 'ayedire', 'boluwaduro', 'boripe', 'ede-north', 'ede-south', 'egbedore', 'ejigbo', 'ife-central', 'ife-east', 'ife-north', 'ife-south', 'ifedayo', 'ifelodun', 'ila', 'ilesa-east', 'ilesa-west', 'irepodun', 'irewole', 'isokan', 'iwo', 'obokun', 'odo-otin', 'ola-oluwa', 'olorunda', 'oriade', 'orolu', 'osogbo'],
  'OY': ['afijio', 'akinyele', 'atiba', 'atisbo', 'egbeda', 'ibadan-north', 'ibadan-north-east', 'ibadan-north-west', 'ibadan-south-west', 'ibadan-south-east', 'ibarapa-central', 'ibarapa-east', 'ibarapa-north', 'ido', 'irepo', 'iseyin', 'itesiwaju', 'iwajowa', 'kajola', 'lagelu', 'ogbomoso-north', 'ogbomoso-south', 'ogo-oluwa', 'olorunsogo', 'oluyole', 'ona-ara', 'orelope', 'ori-ire', 'oyo-east', 'oyo-west', 'saki-east', 'saki-west', 'surulere'],
  'PL': ['barikin-ladi', 'bassa', 'bokkos', 'jos-east', 'jos-north', 'jos-south', 'kanam', 'kanke', 'langtang-north', 'langtang-south', 'mangu', 'mikang', 'pankshin', 'qua\'an-pan', 'riyom', 'shendam', 'wase'],
  'RI': ['abua-odual', 'ahoada-east', 'ahoada-west', 'akuku-toru', 'andoni', 'asari-toru', 'bonny', 'degema', 'eleme', 'emohua', 'etche', 'gokana', 'ikwerre', 'khana', 'obio-akpor', 'ogba-egbema-ndoni', 'ogu-bolo', 'okrika', 'omuma', 'opobo-nkoro', 'oyigbo', 'port-harcourt', 'tai'],
  'SO': ['binji', 'bodinga', 'dange-shuni', 'gada', 'goronyo', 'gudu', 'gwadabawa', 'illela', 'isa', 'kebbe', 'kware', 'rabah', 'sabon-birni', 'shagari', 'silame', 'sokoto-north', 'sokoto-south', 'tambuwal', 'tangaza', 'tureta', 'wamakko', 'wurno', 'yabo'],
  'TA': ['ardo-kola', 'bali', 'donga', 'gashaka', 'gassol', 'ibi', 'jalingo', 'karim-lamido', 'kurmi', 'lau', 'sardauna', 'takum', 'ussa', 'wukari', 'yorro', 'zing'],
  'YO': ['bade', 'bursari', 'damaturu', 'fika', 'fune', 'geidam', 'gujba', 'gulani', 'jakusko', 'karasuwa', 'machina', 'nangere', 'nguru', 'potiskum', 'tarmuwa', 'yunusari', 'yusufari'],
  'ZA': ['anka', 'bakura', 'birnin-magaji', 'bukkuyum', 'bungudu', 'gummi', 'gusau', 'kaura-namoda', 'maradun', 'maru', 'shinkafi', 'talata-mafara', 'tsafe', 'zurmi'],
};

const Map<String, String> nigeriaLgaDisplayOverrides = {
  'abuja-municipal': 'Abuja Municipal Area Council',
  'owerri-urban': 'Owerri Municipal',
  'yewa-egbado-north': 'Yewa North',
  'yewa-egbado-south': 'Yewa South',
  'ogun-water-side': 'Ogun Waterside',
  'abua-odual': 'Abua/Odual',
  'obio-akpor': 'Obio/Akpor',
  'ogba-egbema-ndoni': 'Ogba/Egbema/Ndoni',
  'ogu-bolo': 'Ogu/Bolo',
  'opobo-nkoro': 'Opobo/Nkoro',
  'barikin-ladi': 'Barkin Ladi',
  'koton-karfe': 'Kogi/Koton Karfe',
  'qua\'an-pan': 'Qua\'an Pan',
  'jema\'a': 'Jema\'a',
  'jama\'are': 'Jama\'are',
  'mai\'adua': 'Mai\'Adua',
  'ado-odo-ota': 'Ado-Odo/Ota',
  'urue-offong-oruko': 'Urue-Offong/Oruko',
  'yalmaltu-deba': 'Yamaltu/Deba',
};

String nigeriaLgaDisplayName(String slug) {
  final override = nigeriaLgaDisplayOverrides[slug];
  if (override != null) return override;
  return slug
      .split('-')
      .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
