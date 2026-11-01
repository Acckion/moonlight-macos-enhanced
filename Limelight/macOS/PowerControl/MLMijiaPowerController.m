#import "MLMijiaPowerController.h"
#import "Logger.h"

@interface MLMijiaPowerController ()
@property (nonatomic, strong) NSMutableSet<NSString *> *busyHosts;
@end

@implementation MLMijiaPowerController

+ (instancetype)shared {
    static MLMijiaPowerController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [self new]; controller.busyHosts = [NSMutableSet set]; });
    return controller;
}

- (BOOL)isChinese {
    NSString *language = [[NSUserDefaults standardUserDefaults] stringForKey:@"appLanguage"];
    if (language.length == 0 || [language isEqualToString:@"System"]) language = NSLocale.preferredLanguages.firstObject;
    return [language hasPrefix:@"zh"] || [language isEqualToString:@"简体中文"];
}

- (NSString *)text:(NSString *)zh english:(NSString *)en { return self.isChinese ? zh : en; }

- (NSString *)bindingKey:(NSString *)uuid { return [@"MijiaPowerBinding." stringByAppendingString:uuid]; }

- (NSDictionary *)binding:(NSString *)uuid {
    return [[NSUserDefaults standardUserDefaults] dictionaryForKey:[self bindingKey:uuid]];
}

- (NSMenuItem *)menuItemForHostUUID:(NSString *)uuid name:(NSString *)name {
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:[self text:@"米家电源" english:@"Xiaomi Power"] action:nil keyEquivalent:@""];
    root.identifier = @"mijiaPowerItem";
    root.image = [NSImage imageWithSystemSymbolName:@"powerplug" accessibilityDescription:nil];
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    root.submenu = menu;
    NSDictionary *binding = [self binding:uuid];
    NSArray *commands = @[@"on", @"off", @"status", @"bind"];
    NSArray *titles = @[[self text:@"开机（接通电源）" english:@"Power On"],
                        [self text:@"关机（断电倒计时）…" english:@"Shut Down via Power Guard…"],
                        [self text:@"查看电源状态" english:@"Power Status"],
                        [self text:@"绑定插座…" english:@"Configure Smart Plug…"]];
    for (NSUInteger index = 0; index < commands.count; index++) {
        if (index == 3) [menu addItem:NSMenuItem.separatorItem];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[index] action:@selector(selected:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = @{@"uuid": uuid, @"name": name, @"command": commands[index]};
        item.enabled = ![self.busyHosts containsObject:uuid] && (index == 3 || binding[@"did"] != nil);
        [menu addItem:item];
    }
    return root;
}

- (void)message:(NSString *)title detail:(NSString *)detail {
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = detail;
    [alert addButtonWithTitle:[self text:@"好" english:@"OK"]];
    [alert runModal];
}

- (void)selected:(NSMenuItem *)sender {
    NSDictionary *context = sender.representedObject;
    NSString *uuid = context[@"uuid"];
    NSString *command = context[@"command"];
    if ([self.busyHosts containsObject:uuid]) return;
    if ([command isEqualToString:@"bind"]) {
        [self configure:context];
        return;
    }
    NSDictionary *binding = [self binding:uuid];
    if (!binding[@"did"]) return;
    if ([command isEqualToString:@"off"]) {
        NSAlert *alert = [NSAlert new];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = [self text:@"断开电源并启动关机倒计时？" english:@"Disconnect power and start shutdown countdown?"];
        alert.informativeText = [NSString stringWithFormat:[self text:@"将关闭「%@」供电。Windows 会依靠电池继续运行，并由 Power Guard 倒计时关机。重新接通电源可取消倒计时。请先保存工作。操作前会检查关机保护是否正在运行。" english:@"Power to “%@” will be disconnected. Windows will stay on battery while Power Guard counts down to shutdown. Reconnect power to cancel. Save your work first. The shutdown guard will be checked before disconnecting power."], binding[@"name"]];
        [alert addButtonWithTitle:[self text:@"取消" english:@"Cancel"]];
        [alert addButtonWithTitle:[self text:@"断电并倒计时关机" english:@"Disconnect Power"]];
        if ([alert runModal] != NSAlertSecondButtonReturn) return;
    }
    NSMutableArray *arguments = [NSMutableArray arrayWithArray:@[command, @"--device", binding[@"did"]]];
    if ([command isEqualToString:@"off"]) [arguments addObjectsFromArray:@[@"--guard-host", binding[@"guardHost"] ?: @""]];
    [self run:arguments host:uuid completion:^(NSDictionary *result, NSString *error) {
        if (error) {
            [self message:[self text:@"电源操作未完成" english:@"Power action incomplete"] detail:error];
            return;
        }
        BOOL confirmed = !result[@"outcome"] || [result[@"outcome"] isEqualToString:@"confirmed"];
        if (!confirmed) {
            NSString *detail = [result[@"accepted"] boolValue]
                ? [self text:@"电源指令已被云端接受，但插座状态尚未同步确认。实际电源可能已经切换。请使用“查看电源状态”核对，不要因为此提示重复切换电源。" english:@"The cloud accepted the command, but the plug state has not synchronized yet. Power may already have changed. Use Power Status to check before issuing another action."]
                : [self text:@"发送电源指令后未能确认结果，实际电源可能已经切换。请使用“查看电源状态”或米家 App 核对，不要直接重复操作。" english:@"The outcome could not be confirmed after sending the command. Power may already have changed. Check Power Status or Xiaomi Home before retrying."];
            [self message:[self text:@"电源状态待确认" english:@"Power state pending"] detail:detail];
            return;
        }
        BOOL on = [result[@"on"] boolValue];
        NSString *state = on ? [self text:@"已接通" english:@"On"] : [self text:@"已断开" english:@"Off"];
        id watts = result[@"watts"];
        NSString *power = [watts isKindOfClass:NSNumber.class] ? [NSString stringWithFormat:@"%@ W", watts] : @"—";
        NSString *detail = [NSString stringWithFormat:[self text:@"插座：%@\n供电：%@\n功率：%@" english:@"Plug: %@\nPower: %@\nConsumption: %@"], result[@"name"], state, power];
        if ([command isEqualToString:@"on"]) detail = [detail stringByAppendingString:[self text:@"\n\n插座供电已确认；电脑是否启动成功，请以主机上线为准。若它已经关机但插座仍通电，重复通电不会产生新的开机信号。" english:@"\n\nPlug power is confirmed. Wait for the host to appear online to confirm startup. Turning on an already-on plug does not generate a new power-on signal."]];
        if ([command isEqualToString:@"off"]) detail = [detail stringByAppendingString:[self text:@"\n\n插座断电已确认，尚未确认 Windows 关机完成。需要取消时可选择“开机”重新接通电源。" english:@"\n\nPlug disconnection is confirmed; Windows shutdown is not yet verified. Use Power On to reconnect power and cancel the countdown."]];
        [self message:[self text:@"米家电源" english:@"Xiaomi Power"] detail:detail];
    }];
}

- (void)configure:(NSDictionary *)context {
    NSDictionary *old = [self binding:context[@"uuid"]];
    NSAlert *alert = [NSAlert new];
    alert.messageText = [self text:@"绑定米家插座" english:@"Configure Xiaomi Smart Plug"];
    alert.informativeText = [self text:@"填写米家中的插座名称。请先通过 uvx mijiaAPI login 扫码登录。关机前会通过 SSH 检查 Windows 的 Power Guard 保护。" english:@"Enter the plug name from Xiaomi Home. Sign in first using uvx mijiaAPI login. SSH is used to verify Windows Power Guard before shutdown."];
    NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 110)];
    NSTextField *plugLabel = [NSTextField labelWithString:[self text:@"插座名称" english:@"Plug name"]];
    plugLabel.frame = NSMakeRect(0, 84, 360, 20);
    NSTextField *plugField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 56, 360, 26)];
    plugField.stringValue = old[@"name"] ?: @"PC控制插座";
    NSTextField *sshLabel = [NSTextField labelWithString:[self text:@"关机保护检查 · SSH 主机别名" english:@"Shutdown guard · SSH host alias"]];
    sshLabel.frame = NSMakeRect(0, 28, 360, 20);
    NSTextField *sshField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 360, 26)];
    sshField.stringValue = old[@"guardHost"] ?: @"r9000p";
    for (NSView *view in @[plugLabel, plugField, sshLabel, sshField]) [form addSubview:view];
    alert.accessoryView = form;
    [alert addButtonWithTitle:[self text:@"取消" english:@"Cancel"]];
    [alert addButtonWithTitle:[self text:@"验证并绑定" english:@"Verify and Bind"]];
    if ([alert runModal] != NSAlertSecondButtonReturn) return;
    NSString *name = [plugField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *alias = [sshField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0 || alias.length == 0) return;
    [self run:@[@"resolve", @"--name", name] host:context[@"uuid"] completion:^(NSDictionary *result, NSString *error) {
        if (error) { [self message:[self text:@"绑定失败" english:@"Binding failed"] detail:error]; return; }
        NSDictionary *binding = @{@"did": result[@"did"], @"name": result[@"name"], @"guardHost": alias};
        [[NSUserDefaults standardUserDefaults] setObject:binding forKey:[self bindingKey:context[@"uuid"]]];
        [self message:[self text:@"插座已绑定" english:@"Smart plug configured"] detail:[NSString stringWithFormat:[self text:@"「%@」已绑定到「%@」。未执行电源开关操作。" english:@"“%@” is now bound to “%@”. No power switching was performed."], result[@"name"], context[@"name"]]];
    }];
}

- (void)run:(NSArray<NSString *> *)arguments host:(NSString *)uuid completion:(void (^)(NSDictionary *, NSString *))completion {
    NSString *uv;
    for (NSString *candidate in @[@"/opt/homebrew/bin/uv", @"/usr/local/bin/uv"]) {
        if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate]) { uv = candidate; break; }
    }
    NSString *helper = [NSBundle.mainBundle pathForResource:@"mijia_power" ofType:@"py"];
    if (!uv || !helper) {
        completion(nil, [self text:@"未找到米家控制组件或 uv。请安装 uv，并确保使用包含电源控制组件的应用版本。" english:@"The Xiaomi helper or uv could not be found. Install uv and use a build containing the power helper."]);
        return;
    }
    [self.busyHosts addObject:uuid];
    NSAlert *progress = [NSAlert new];
    progress.messageText = [self text:@"正在联系米家云端…" english:@"Contacting Xiaomi Cloud…"];
    progress.informativeText = [self text:@"正在核对插座状态，请稍候。" english:@"Checking the smart plug. Please wait."];
    [progress addButtonWithTitle:[self text:@"处理中…" english:@"Working…"]].enabled = NO;
    NSWindow *window = NSApp.keyWindow;
    if (window) [progress beginSheetModalForWindow:window completionHandler:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:uv];
        task.arguments = [@[@"run", @"--no-project", @"--script", helper] arrayByAddingObjectsFromArray:arguments];
        NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
        environment[@"PATH"] = @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        environment[@"UV_NO_PROGRESS"] = @"1";
        environment[@"PYTHONUNBUFFERED"] = @"1";
        task.environment = environment;
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        // Dependencies may print progress to stderr. Never place raw authentication errors in UI.
        task.standardError = NSFileHandle.fileHandleWithNullDevice;
        NSError *launchError;
        BOOL started = [task launchAndReturnError:&launchError];
        __block BOOL timedOut = NO;
        dispatch_block_t timeout = dispatch_block_create(0, ^{
            if (task.running) { timedOut = YES; [task terminate]; }
        });
        if (started) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 90 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), timeout);
        NSData *data = started ? [pipe.fileHandleForReading readDataToEndOfFile] : nil;
        if (started) [task waitUntilExit];
        dispatch_block_cancel(timeout);
        NSDictionary *result;
        NSString *output = [[NSString alloc] initWithData:data ?: NSData.data encoding:NSUTF8StringEncoding];
        // Library informational logging may precede the helper's final JSON line.
        for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
            id value = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];
            if ([value isKindOfClass:NSDictionary.class]) result = value;
        }
        NSString *error = result[@"error"];
        if (timedOut) error = [self text:@"云端请求超时，结果未知。请先查询电源状态，再决定是否重试。" english:@"The request timed out; the outcome is unknown. Check Power Status before retrying."];
        if (!error && (!started || task.terminationStatus != 0 || !result[@"did"])) error = [self text:@"米家控制失败。请检查网络、uv 和米家登录状态。" english:@"Xiaomi control failed. Check the network, uv installation and Xiaomi sign-in."];
        Log(error ? LOG_W : LOG_I, @"[mijia-power] command=%@ exit=%d timeout=%d result=%d outcome=%@",
            arguments.firstObject, started ? task.terminationStatus : -1, timedOut,
            result[@"did"] != nil, result[@"outcome"] ?: @"unavailable");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.busyHosts removeObject:uuid];
            if (window) [window endSheet:progress.window];
            completion(result, error);
        });
    });
}
@end
