package main

// Alter's bounded index adapter. Compiled alongside pinned Mole, reusing its
// allocated-size accounting. No contents, symlink traversal, or cleanup calls.
import (
 "bufio"
 "encoding/json"
 "fmt"
 "io"
 "os"
 "path/filepath"
 "syscall"
 "unicode/utf8"
)
type alterNode struct {
 Path string `json:"path"`
 Parent string `json:"parent"`
 Name string `json:"name"`
 Size int64 `json:"size"`
 Logical int64 `json:"logical"`
 Modified int64 `json:"modified"`
 Identity string `json:"identity"`
 Kind string `json:"kind"`
 Files int64 `json:"files"`
 Issue string `json:"issue"`
}
func runAlterIndex(root string) error {
 target := filepath.Join(os.Getenv("TMPDIR"), "index.ndjson")
 out, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
 if err != nil { return err }; defer out.Close()
 buffer := bufio.NewWriterSize(out, 65536)
 encoder := json.NewEncoder(buffer)
 var count, written int64
 rootInfo, err := os.Lstat(root); if err != nil { return err }
 rootStat, ok := rootInfo.Sys().(*syscall.Stat_t); if !ok { return fmt.Errorf("unsupported filesystem") }
 emit := func(n alterNode) error {
  if count >= 2000000 || written >= 480*1024*1024 { return fmt.Errorf("index budget reached; choose a smaller root") }
  if !utf8.ValidString(n.Path) { return fmt.Errorf("filename is not valid UTF-8") }
  count++; written += int64(len(n.Path)+len(n.Parent)+len(n.Name)+256)
  return encoder.Encode(n)
 }
 var walk func(string, string, int) (int64, int64, error)
 walk = func(path, parent string, depth int) (int64, int64, error) {
  n := alterNode{Path:path, Parent:parent, Name:filepath.Base(path), Kind:"other"}
  info, e := os.Lstat(path)
  if e != nil { n.Issue = "metadata unavailable"; return 0,0,emit(n) }
  st, ok := info.Sys().(*syscall.Stat_t); if !ok { return 0,0,fmt.Errorf("unsupported metadata") }
  n.Modified = info.ModTime().Unix(); n.Identity = fmt.Sprintf("%d:%d",st.Dev,st.Ino)
  n.Logical = info.Size()
  if info.Mode()&os.ModeSymlink != 0 { n.Kind="link"; n.Size=getActualFileSize(path,info); n.Issue="symbolic link; not followed"; return n.Size,0,emit(n) }
  if info.Mode().IsRegular() { n.Kind="file"; n.Size=getActualFileSize(path,info); n.Files=1; return n.Size,1,emit(n) }
  if !info.IsDir() { return 0,0,emit(n) }
  n.Kind="dir"
  if st.Dev != rootStat.Dev { n.Issue="other volume; scan separately"; return 0,0,emit(n) }
  if depth >= 128 { n.Issue="depth limit"; return 0,0,emit(n) }
  fd, e := syscall.Open(path, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_CLOEXEC,0)
  if e != nil { n.Issue="directory access denied"; return 0,0,emit(n) }
  dir := os.NewFile(uintptr(fd),path); defer dir.Close()
  opened, e := dir.Stat(); if e != nil || !os.SameFile(info,opened) { return 0,0,fmt.Errorf("directory changed during scan") }
  for {
   entries, e := dir.ReadDir(128)
   for _, entry := range entries {
    size, files, err := walk(filepath.Join(path,entry.Name()),path,depth+1)
    if err != nil { return 0,0,err }; n.Size+=size; n.Files+=files
   }
   if e == io.EOF { break }; if e != nil { n.Issue="directory listing incomplete"; break }
  }
  return n.Size,n.Files,emit(n)
 }
 _,_,err = walk(root,"",0); if err != nil { return err }
 if err = buffer.Flush(); err != nil { return err }
 if err = out.Sync(); err != nil { return err }
 return json.NewEncoder(os.Stdout).Encode(map[string]interface{}{"root":root,"nodes":count,"schema":1})
}
