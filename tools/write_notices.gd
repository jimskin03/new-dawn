extends SceneTree

func _initialize() -> void:
 var file=FileAccess.open("res://docs/third_party/Godot.txt",FileAccess.WRITE)
 file.store_string("GODOT ENGINE\n============\n\n"+Engine.get_license_text()+"\n\nTHIRD-PARTY COMPONENTS\n======================\n\n")
 for entry in Engine.get_copyright_info():
  file.store_string(str(entry.get("name",""))+"\n")
  for part in entry.get("parts",[]):
   for copyright in part.get("copyright",[]):file.store_string(str(copyright)+"\n")
   file.store_string("License: "+str(part.get("license",""))+"\n")
  file.store_string("\n")
 var licenses=Engine.get_license_info()
 for name in licenses:file.store_string("\n"+str(name)+"\n"+str(licenses[name])+"\n")
 file.close();print("NOTICES_OK");quit()
