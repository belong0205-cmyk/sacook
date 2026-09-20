#import "../Sources/SCProfileDocument.h"
int main(int argc,const char **argv) { @autoreleasepool {
    if(argc!=2) return 2; NSString *root=[NSString stringWithUTF8String:argv[1]];
    NSArray *cases=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"cases.json"]] options:0 error:nil];
    NSUInteger failures=0, checks=0;
    for(NSDictionary *test in cases) {
      NSError *error=nil; NSString *text=SCReadProfileDocument([NSURL fileURLWithPath:[root stringByAppendingPathComponent:test[@"file"]]],&error);
      checks++; BOOL ok=[test[@"error"] boolValue]?(!text && error):(text.length && !error);
      for(NSString *part in test[@"includes"]) ok=ok && [text containsString:part];
      for(NSString *part in test[@"excludes"]) ok=ok && ![text containsString:part];
      if(!ok) { failures++; fprintf(stderr,"FAIL document fixture: %s\n",[test[@"file"] UTF8String]); }
    }
    fprintf(stdout,"Native Word import: %lu cases, %lu failures\n",checks,failures); return failures?1:0;
} }
