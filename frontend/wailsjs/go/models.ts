export namespace main {
	
	export class HashResult {
	    MD5: string;
	    SHA1: string;
	    SHA256: string;
	    SHA512: string;
	    SM3: string;
	    CRC32: string;
	    CRC64_ISO: string;
	    CRC64_ECMA: string;
	
	    static createFrom(source: any = {}) {
	        return new HashResult(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.MD5 = source["MD5"];
	        this.SHA1 = source["SHA1"];
	        this.SHA256 = source["SHA256"];
	        this.SHA512 = source["SHA512"];
	        this.SM3 = source["SM3"];
	        this.CRC32 = source["CRC32"];
	        this.CRC64_ISO = source["CRC64_ISO"];
	        this.CRC64_ECMA = source["CRC64_ECMA"];
	    }
	}
	export class Hasher {
	    filePath: string;
	    fileName: string;
	    fileSize: string;
	    hashResult: HashResult;
	
	    static createFrom(source: any = {}) {
	        return new Hasher(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.filePath = source["filePath"];
	        this.fileName = source["fileName"];
	        this.fileSize = source["fileSize"];
	        this.hashResult = this.convertValues(source["hashResult"], HashResult);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}

}

